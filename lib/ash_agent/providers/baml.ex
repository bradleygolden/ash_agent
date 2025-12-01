defmodule AshAgent.Providers.Baml do
  @moduledoc """
  AshAgent provider implementation that delegates execution to BAML functions.

  This provider integrates BAML (Boundary ML) with AshAgent to enable
  type-safe LLM interactions through BAML functions.

  ## Usage

  Configure your agent to use the BAML provider:

      agent do
        provider :baml
        client :support, function: :ChatAgent
        output MyApp.BamlClients.Support.Types.ChatAgent
        prompt \"\"\"Prompt is unused for BAML, but required by DSL\"\"\"
      end

  The client can reference:
    * A BAML client identifier configured under `config :ash_baml, :clients`
    * A BAML client module that `use BamlElixir.Client`

  ## Architecture

  This provider lives in ash_agent (not ash_baml) to avoid circular dependencies.
  It uses ash_baml as an optional soft dependency, checked at runtime via
  `Code.ensure_loaded?/1`.

  This allows:
  - ash_baml to be a standalone package with no ash_agent dependency
  - ash_agent to optionally use BAML when ash_baml is installed
  - Proper hex publication of both packages independently
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
      if function_exported?(function_module, :stream, 2) or
           function_exported?(function_module, :stream, 3) do
        {:ok, create_stream(function_module, args, baml_opts)}
      else
        {:error,
         Error.llm_error(
           "BAML function #{inspect(function_module)} does not support streaming",
           %{function: function_name}
         )}
      end
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

  defp fetch_arguments_from_context(%AshAgent.Context{input: input}) when is_map(input),
    do: {:ok, input}

  defp fetch_arguments_from_context(%AshAgent.Context{input: input}) when is_list(input),
    do: {:ok, Map.new(input)}

  defp fetch_arguments_from_context(%{input: input}) when is_map(input), do: {:ok, input}

  defp fetch_arguments_from_context(%{input: input}) when is_list(input),
    do: {:ok, Map.new(input)}

  defp fetch_arguments_from_context(_context) do
    {:error, Error.llm_error("BAML provider requires input arguments but none were provided")}
  end

  defp resolve_client_module(client, opts) do
    case Keyword.get(opts, :client_module) do
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
    # Use soft dependency on AshBaml.ClientBuilder - only available if ash_baml is installed
    if Code.ensure_loaded?(AshBaml.ClientBuilder) do
      case AshBaml.ClientBuilder.ensure_configured_client_module(identifier) do
        {:ok, module} ->
          {:ok, module}

        {:error, reason} when is_binary(reason) ->
          {:error, Error.config_error(reason, %{client: identifier})}

        {:error, reason} ->
          {:error,
           Error.config_error(
             "Failed to resolve BAML client #{inspect(identifier)}: #{inspect(reason)}",
             %{client: identifier}
           )}
      end
    else
      {:error,
       Error.config_error(
         "BAML provider requires ash_baml package. Add {:ash_baml, \"~> 0.1.0\"} to your dependencies.",
         %{
           client: identifier
         }
       )}
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
    collector = create_collector(function_module)
    opts_with_collector = Map.put(opts, :collectors, [collector])

    result =
      cond do
        function_exported?(function_module, :call, 2) ->
          function_module.call(args, opts_with_collector)

        function_exported?(function_module, :call, 1) ->
          function_module.call(args)

        true ->
          {:error,
           Error.config_error(
             "BAML function #{inspect(function_module)} does not define call/1 or call/2"
           )}
      end

    wrap_with_response(result, collector)
  end

  defp create_collector(function_module) do
    name = "#{inspect(function_module)}-#{System.unique_integer([:positive])}"
    BamlElixir.Collector.new(name)
  end

  defp wrap_with_response({:ok, data}, collector) do
    {:ok, AshBaml.Response.new(data, collector)}
  end

  defp wrap_with_response({:error, _} = error, _collector), do: error

  defp create_stream(function_module, arguments, opts) do
    collector = create_collector(function_module)
    opts_with_collector = Map.put(opts, :collectors, [collector])

    Stream.resource(
      fn -> start_streaming(function_module, arguments, opts_with_collector, collector) end,
      &stream_next/1,
      &cleanup_stream/1
    )
  end

  defp start_streaming(function_module, arguments, opts, collector) do
    parent = self()
    ref = make_ref()
    stream_fn = build_stream_callback(parent, ref)

    result =
      if function_exported?(function_module, :stream, 3) do
        function_module.stream(arguments, stream_fn, opts)
      else
        function_module.stream(arguments, stream_fn)
      end

    handle_stream_result(result, ref, collector)
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

  defp handle_stream_result(result, ref, collector) do
    case result do
      {:ok, stream_pid} when is_pid(stream_pid) ->
        {ref, stream_pid, :streaming, collector}

      pid when is_pid(pid) ->
        {ref, pid, :streaming, collector}

      {:error, reason} ->
        {ref, nil, {:error, reason}, collector}

      other when is_function(other) ->
        {ref, nil, {:error, "BAML stream function returned a function instead of a stream"},
         collector}

      other ->
        {ref, nil, {:error, "Unexpected stream result: #{inspect(other)}"}, collector}
    end
  end

  defp stream_next({ref, stream_pid, :streaming, collector}) do
    receive do
      {^ref, :chunk, chunk} ->
        if valid_chunk?(chunk) do
          {[chunk], {ref, stream_pid, :streaming, collector}}
        else
          {[], {ref, stream_pid, :streaming, collector}}
        end

      {^ref, :done, {:ok, final_result}} ->
        wrapped = AshBaml.Response.new(final_result, collector)
        {[wrapped], {ref, stream_pid, :done, collector}}

      {^ref, :done, {:error, reason}} ->
        {:halt, {ref, stream_pid, {:error, reason}, collector}}
    after
      @default_stream_timeout ->
        {:halt,
         {ref, stream_pid,
          {:error,
           "Stream timeout after #{@default_stream_timeout}ms - BAML process may have crashed"},
          collector}}
    end
  end

  defp stream_next({ref, stream_pid, :done, collector}),
    do: {:halt, {ref, stream_pid, :done, collector}}

  defp stream_next({ref, stream_pid, {:error, reason}, collector}),
    do: {:halt, {ref, stream_pid, {:error, reason}, collector}}

  defp cleanup_stream({ref, _stream_pid, _status, _collector}) do
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
        :prompt_optional,
        :schema_optional
      ],
      constraints: %{requires_function: true}
    }
  end

  @impl true
  def extract_content(%_{} = response) do
    struct_name = response.__struct__ |> Module.split() |> List.last()
    struct_map = Map.from_struct(response)

    if tool_call_struct?(struct_name, struct_map) do
      {:ok, ""}
    else
      case Map.get(struct_map, :content) do
        content when is_binary(content) -> {:ok, content}
        _ -> {:ok, ""}
      end
    end
  end

  def extract_content(_response), do: :default

  @impl true
  def extract_tool_calls(%_{} = response) do
    struct_map = Map.from_struct(response)
    struct_name = response.__struct__ |> Module.split() |> List.last()

    tool_calls =
      if tool_call_struct_name?(struct_name) do
        extract_single_tool_call(struct_map)
      else
        extract_tool_calls_from_map(struct_map)
      end

    {:ok, tool_calls}
  end

  def extract_tool_calls(_response), do: :default

  @impl true
  def extract_thinking(%AshBaml.Response{} = response), do: AshBaml.Response.thinking(response)
  def extract_thinking(_response), do: nil

  @impl true
  def extract_metadata(%AshBaml.Response{} = response) do
    %{
      provider: :baml,
      duration_ms: get_in(response.timing, [:duration_ms]),
      time_to_first_token_ms: get_in(response.timing, [:time_to_first_token_ms]),
      started_at: convert_utc_ms_to_datetime(get_in(response.timing, [:start_time_utc_ms])),
      request_id: response.request_id,
      client_name: response.client_name,
      num_attempts: response.num_attempts,
      tags: response.tags,
      raw_http_response: response.http_response_body
    }
  end

  def extract_metadata(_response), do: :default

  defp convert_utc_ms_to_datetime(nil), do: nil

  defp convert_utc_ms_to_datetime(ms) when is_number(ms) do
    case DateTime.from_unix(trunc(ms), :millisecond) do
      {:ok, dt} -> dt
      _ -> nil
    end
  end

  defp convert_utc_ms_to_datetime(_), do: nil

  # Private helpers for BAML-specific extraction

  defp tool_call_struct?(struct_name, struct_map) do
    tool_call_struct_name?(struct_name) or
      has_tool_call_fields?(struct_map) or
      has_tool_call_type?(struct_map)
  end

  defp tool_call_struct_name?(struct_name) do
    String.contains?(struct_name, "ToolCall") and not String.contains?(struct_name, "Response")
  end

  defp has_tool_call_fields?(struct_map) do
    Map.has_key?(struct_map, :tool_name) or Map.has_key?(struct_map, :tool_arguments)
  end

  defp has_tool_call_type?(struct_map) do
    Map.has_key?(struct_map, :__type__) and struct_map.__type__ in ["tool_call", "ToolCall"]
  end

  defp extract_single_tool_call(struct_map) do
    cond do
      Map.has_key?(struct_map, :tool_name) ->
        [build_normalized_tool_call(struct_map.tool_name, get_tool_arguments(struct_map))]

      Map.has_key?(struct_map, :name) ->
        [build_normalized_tool_call(struct_map.name, Map.get(struct_map, :arguments, %{}))]

      true ->
        []
    end
  end

  defp extract_tool_calls_from_map(struct_map) do
    cond do
      Map.has_key?(struct_map, :tool_calls) and is_list(struct_map.tool_calls) ->
        Enum.flat_map(struct_map.tool_calls, &extract_tool_call_item/1)

      Map.has_key?(struct_map, :tools) and is_list(struct_map.tools) ->
        Enum.flat_map(struct_map.tools, &extract_tool_call_item/1)

      has_tool_call_fields?(struct_map) ->
        extract_single_tool_call(struct_map)

      true ->
        []
    end
  end

  defp extract_tool_call_item(%_{} = item) do
    item_map = Map.from_struct(item)
    extract_single_tool_call(item_map)
  end

  defp extract_tool_call_item(item) when is_map(item) do
    extract_single_tool_call(item)
  end

  defp extract_tool_call_item(_item), do: []

  defp get_tool_arguments(struct_map) do
    cond do
      Map.has_key?(struct_map, :tool_arguments) ->
        struct_map.tool_arguments

      Map.has_key?(struct_map, :arguments) ->
        struct_map.arguments

      true ->
        %{}
    end
  end

  defp build_normalized_tool_call(name, arguments) when is_binary(name) do
    %{
      "id" => generate_tool_call_id(),
      "name" => name,
      "arguments" => normalize_arguments(arguments)
    }
  end

  defp build_normalized_tool_call(name, arguments) when is_atom(name) do
    build_normalized_tool_call(Atom.to_string(name), arguments)
  end

  defp build_normalized_tool_call(_name, _arguments), do: %{}

  defp normalize_arguments(args) when is_map(args) do
    Map.new(args, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp normalize_arguments(_args), do: %{}

  defp generate_tool_call_id do
    "baml_" <> Base.encode16(:crypto.strong_rand_bytes(8), case: :lower)
  end
end
