defmodule AshAgent.Providers.Baml do
  @moduledoc """
  Provider implementation that delegates execution to BAML functions.

  This adapter allows AshAgent resources to reuse BAML clients defined via
  [`ash_baml`](https://github.com/bradleygolden/ash_baml) without duplicating
  orchestration logic. It expects the agent's `client` configuration to point to
  either:

    * A BAML client identifier configured under `config :ash_baml, :clients`
    * A BAML client module that `use BamlElixir.Client`

  Additional options (e.g., the function name) are supplied via the agent DSL:

      agent do
        provider :baml
        client :support, function: :ChatAgent
        output MyApp.BamlClients.Support.Types.ChatAgent
        prompt \"\"\"Prompt is unused for BAML, but required by DSL\"\"\"
      end
  """

  @behaviour AshAgent.Provider

  alias AshAgent.Error

  @default_stream_timeout 30_000

  @impl true
  def call(client, _prompt, _schema, opts, context, tools, messages) do
    with {:ok, function_name} <- fetch_function(opts),
         {:ok, args} <- fetch_arguments(context, messages),
         {:ok, client_module} <- resolve_client_module(client, opts),
         {:ok, function_module} <- resolve_function_module(client_module, function_name),
         {:ok, baml_opts} <- build_baml_opts(opts, tools, messages),
         {:ok, result} <- invoke_function(function_module, args, baml_opts) do
      {:ok, result}
    else
      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error,
         Error.llm_error("BAML provider call failed", %{
           reason: reason,
           client: client
         })}
    end
  rescue
    e ->
      {:error,
       Error.llm_error("BAML provider call crashed", %{
         client: client,
         exception: e
       })}
  end

  @impl true
  def stream(client, _prompt, _schema, opts, context, tools, messages) do
    with {:ok, function_name} <- fetch_function(opts),
         {:ok, args} <- fetch_arguments(context, messages),
         {:ok, client_module} <- resolve_client_module(client, opts),
         {:ok, function_module} <- resolve_function_module(client_module, function_name),
         {:ok, baml_opts} <- build_baml_opts(opts, tools, messages) do
      cond do
        function_exported?(function_module, :stream, 2) or
            function_exported?(function_module, :stream, 3) ->
          {:ok, create_stream(function_module, args, baml_opts)}

        true ->
          {:error,
           Error.llm_error(
             "BAML function #{inspect(function_module)} does not support streaming",
             %{function: function_name}
           )}
      end
    else
      {:error, %Error{} = error} ->
        {:error, error}

      {:error, reason} ->
        {:error,
         Error.llm_error("BAML provider stream failed", %{
           reason: reason,
           client: client
         })}
    end
  end

  defp fetch_function(opts) do
    case Keyword.fetch(opts, :function) do
      {:ok, name} when is_atom(name) ->
        {:ok, name}

      {:ok, other} ->
        {:error,
         Error.config_error("BAML provider requires function option to be an atom", %{
           provided: other
         })}

      :error ->
        {:error,
         Error.config_error("BAML provider requires :function option in client configuration")}
    end
  end

  defp fetch_arguments(context, _messages) do
    fetch_arguments_from_context(context)
  end

  defp fetch_arguments_from_context(%{input: input}) when is_map(input), do: {:ok, input}

  defp fetch_arguments_from_context(%{input: input}) when is_list(input),
    do: {:ok, Map.new(input)}

  defp fetch_arguments_from_context(_context) do
    {:error, Error.llm_error("BAML provider requires input arguments but none were provided")}
  end

  defp resolve_client_module(client, opts) do
    case Keyword.get(opts || [], :client_module) do
      nil ->
        resolve_client_from_value(client)

      module when is_atom(module) ->
        {:ok, module}

      other ->
        {:error, Error.config_error(":client_module must be a module atom", %{provided: other})}
    end
  end

  defp resolve_client_from_value(client) when is_atom(client) do
    if Code.ensure_loaded?(client) do
      {:ok, client}
    else
      lookup_configured_client(client)
    end
  end

  defp resolve_client_from_value(client) do
    {:error,
     Error.config_error("Unsupported BAML client specification", %{
       client: client
     })}
  end

  defp lookup_configured_client(identifier) do
    clients = Application.get_env(:ash_baml, :clients, [])

    case Keyword.get(clients, identifier) do
      {module, _opts} ->
        {:ok, module}

      nil ->
        {:error,
         Error.config_error("No BAML client configured for #{inspect(identifier)}", %{
           client: identifier
         })}
    end
  end

  defp resolve_function_module(client_module, function_name) do
    module = Module.concat(client_module, function_name)

    if Code.ensure_loaded?(module) do
      {:ok, module}
    else
      {:error,
       Error.config_error(
         "BAML function module #{inspect(module)} is not available. Ensure your BAML client compiled the function.",
         %{
           client_module: client_module,
           function: function_name
         }
       )}
    end
  end

  defp build_baml_opts(opts, tools, messages) do
    baml_opts =
      opts
      |> Keyword.get(:baml_opts, %{})
      |> to_map_opts()
      |> maybe_add_tools(tools)
      |> maybe_add_messages(messages)

    {:ok, baml_opts}
  end

  defp maybe_add_tools(opts, nil), do: opts
  defp maybe_add_tools(opts, []), do: opts

  defp maybe_add_tools(opts, tools) when is_list(tools) do
    Map.put(opts, :tools, tools)
  end

  defp maybe_add_messages(opts, nil), do: opts

  defp maybe_add_messages(opts, messages) when is_list(messages) do
    Map.put(opts, :messages, messages)
  end

  defp maybe_add_messages(opts, _messages), do: opts

  defp invoke_function(function_module, args, opts) do
    cond do
      function_exported?(function_module, :call, 2) ->
        function_module.call(args, opts)

      function_exported?(function_module, :call, 1) ->
        function_module.call(args)

      true ->
        {:error,
         Error.config_error(
           "BAML function #{inspect(function_module)} does not define call/1 or call/2"
         )}
    end
  end

  defp create_stream(function_module, arguments, opts) do
    Stream.resource(
      fn -> start_streaming(function_module, arguments, opts) end,
      &stream_next/1,
      &cleanup_stream/1
    )
  end

  defp start_streaming(function_module, arguments, opts) do
    parent = self()
    ref = make_ref()
    stream_fn = build_stream_callback(parent, ref)

    result =
      cond do
        function_exported?(function_module, :stream, 3) ->
          try do
            function_module.stream(arguments, opts, stream_fn)
          rescue
            FunctionClauseError -> function_module.stream(arguments, stream_fn, opts)
          end

        true ->
          function_module.stream(arguments, stream_fn)
      end

    handle_stream_result(result, ref)
  end

  defp build_stream_callback(parent, ref) do
    fn
      {:partial, partial_result} ->
        send(parent, {ref, :chunk, partial_result})

      {:done, final_result} ->
        send(parent, {ref, :done, {:ok, final_result}})

      {:error, error} ->
        send(parent, {ref, :done, {:error, error}})
    end
  end

  defp handle_stream_result(result, ref) do
    case result do
      {:ok, stream_pid} when is_pid(stream_pid) ->
        {ref, stream_pid, :streaming}

      pid when is_pid(pid) ->
        {ref, pid, :streaming}

      {:error, reason} ->
        {ref, nil, {:error, reason}}

      other when is_function(other) ->
        {ref, nil, {:error, "BAML stream function returned a function instead of a stream"}}

      other ->
        {ref, nil, {:error, "Unexpected stream result: #{inspect(other)}"}}
    end
  end

  defp stream_next({ref, stream_pid, :streaming}) do
    receive do
      {^ref, :chunk, chunk} ->
        if valid_chunk?(chunk) do
          {[chunk], {ref, stream_pid, :streaming}}
        else
          {[], {ref, stream_pid, :streaming}}
        end

      {^ref, :done, {:ok, final_result}} ->
        {[final_result], {ref, stream_pid, :done}}

      {^ref, :done, {:error, reason}} ->
        {:halt, {ref, stream_pid, {:error, reason}}}
    after
      @default_stream_timeout ->
        {:halt,
         {ref, stream_pid,
          {:error,
           "Stream timeout after #{@default_stream_timeout}ms - BAML process may have crashed"}}}
    end
  end

  defp stream_next({ref, stream_pid, :done}), do: {:halt, {ref, stream_pid, :done}}

  defp stream_next({ref, stream_pid, {:error, reason}}),
    do: {:halt, {ref, stream_pid, {:error, reason}}}

  defp cleanup_stream({ref, _stream_pid, _status}) do
    flush_stream_messages(ref)
    :ok
  end

  defp flush_stream_messages(ref, remaining \\ 10_000)
  defp flush_stream_messages(_ref, 0), do: :ok

  defp flush_stream_messages(ref, remaining) do
    receive do
      {^ref, _, _} -> flush_stream_messages(ref, remaining - 1)
    after
      0 -> :ok
    end
  end

  defp valid_chunk?(chunk) when is_struct(chunk), do: not is_nil(Map.get(chunk, :content))

  defp valid_chunk?(_chunk), do: true

  defp to_map_opts(opts) when is_map(opts), do: opts
  defp to_map_opts(opts) when is_list(opts), do: Map.new(opts)
  defp to_map_opts(_), do: %{}

  @impl true
  def introspect do
    %{
      provider: :baml,
      features: [
        :sync_call,
        :streaming,
        :structured_output,
        :tool_calling,
        :prompt_optional
      ],
      constraints: %{requires_function: true}
    }
  end
end
