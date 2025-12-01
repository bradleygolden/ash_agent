defmodule AshAgent.Providers.ReqLLM do
  @moduledoc """
  Provider implementation for ReqLLM library.

  Wraps the existing ReqLLM integration to conform to the
  AshAgent.Provider behavior. Preserves all existing functionality
  including retry logic.

  ## Configuration

      agent do
        provider :req_llm,
          client: "anthropic:claude-3-5-sonnet",
          temperature: 0.7,
          max_tokens: 4096
      end

  ## Features

  - Synchronous and streaming calls
  - Automatic retry with exponential backoff
  - Structured output via JSON schema
  - Multiple model support (Anthropic, OpenAI, etc.)
  """

  @behaviour AshAgent.Provider

  require Logger

  @impl true
  def call(client, prompt, schema, opts, _context, tools, messages) do
    max_attempts = Keyword.get(opts, :max_retries, 3)
    base_delay_ms = Keyword.get(opts, :retry_base_delay_ms, 100)

    {prompt_or_messages, req_opts} = build_req_args(prompt, messages, opts, tools)

    with_retry(
      fn ->
        if is_nil(schema) or primitive_schema?(schema) do
          ReqLLM.generate_text(client, prompt_or_messages, req_opts)
        else
          ReqLLM.generate_object(client, prompt_or_messages, schema, req_opts)
        end
      end,
      max_attempts,
      base_delay_ms
    )
  end

  @impl true
  def stream(client, prompt, schema, opts, _context, tools, messages) do
    {prompt_or_messages, req_opts} = build_req_args(prompt, messages, opts, tools)

    if is_nil(schema) or primitive_schema?(schema) do
      ReqLLM.stream_text(client, prompt_or_messages, req_opts)
    else
      ReqLLM.stream_object(client, prompt_or_messages, schema, req_opts)
    end
  end

  defp primitive_schema?(schema) when schema in [:string, :integer, :boolean, :float, :number],
    do: true

  defp primitive_schema?(_), do: false

  defp build_req_args(prompt, messages, opts, tools) do
    prompt_or_messages = if messages && length(messages) > 0, do: messages, else: prompt

    req_opts = opts |> maybe_add_tools(tools)

    {prompt_or_messages, req_opts}
  end

  defp maybe_add_tools(opts, nil), do: opts
  defp maybe_add_tools(opts, []), do: opts

  defp maybe_add_tools(opts, tools) when is_list(tools) do
    Keyword.put(opts, :tools, tools)
  end

  @impl true
  def introspect do
    %{
      provider: :req_llm,
      features: [
        :sync_call,
        :streaming,
        :structured_output,
        :function_calling,
        :tool_calling,
        :auto_retry
      ],
      models: available_models()
    }
  end

  @impl true
  def extract_content(%ReqLLM.Response{} = response) do
    case ReqLLM.Response.unwrap_object(response) do
      {:ok, object} when is_map(object) ->
        case Map.get(object, "content") || Map.get(object, :content) do
          nil -> {:ok, ""}
          content when is_binary(content) -> {:ok, content}
          content when is_list(content) -> {:ok, extract_text_from_content_blocks(content)}
          _ -> {:ok, ""}
        end

      _ ->
        {:ok, ""}
    end
  end

  def extract_content(_response), do: :default

  @impl true
  def extract_tool_calls(%ReqLLM.Response{} = response) do
    tool_calls = ReqLLM.Response.tool_calls(response)

    if is_list(tool_calls) do
      {:ok, tool_calls}
    else
      {:ok, []}
    end
  end

  def extract_tool_calls(_response), do: :default

  @impl true
  def extract_thinking(%ReqLLM.Response{} = response) do
    case ReqLLM.Response.thinking(response) do
      "" -> nil
      nil -> nil
      text -> text
    end
  end

  def extract_thinking(_response), do: :default

  @impl true
  def extract_metadata(%ReqLLM.Response{} = response) do
    usage = ReqLLM.Response.usage(response) || %{}

    %{
      provider: :req_llm,
      reasoning_tokens: Map.get(usage, :reasoning_tokens),
      cached_tokens: Map.get(usage, :cached_tokens) || Map.get(usage, :cache_read_input_tokens),
      input_cost: Map.get(usage, :input_cost),
      output_cost: Map.get(usage, :output_cost),
      total_cost: Map.get(usage, :total_cost)
    }
  end

  def extract_metadata(_response), do: :default

  defp extract_text_from_content_blocks([%{"type" => "text", "text" => text} | _])
       when is_binary(text),
       do: text

  defp extract_text_from_content_blocks([%{type: "text", text: text} | _]) when is_binary(text),
    do: text

  defp extract_text_from_content_blocks([_ | rest]), do: extract_text_from_content_blocks(rest)
  defp extract_text_from_content_blocks([]), do: ""

  defp with_retry(func, attempts_left, base_delay_ms, attempt_num \\ 1)

  defp with_retry(_func, 0, _base_delay_ms, attempt_num) do
    Logger.error("ReqLLM provider: All retry attempts exhausted (#{attempt_num - 1} attempts)")
    {:error, :max_retries_exceeded}
  end

  defp with_retry(func, 1, _base_delay_ms, _attempt_num) do
    func.()
  end

  defp with_retry(func, attempts_left, base_delay_ms, attempt_num) when attempts_left > 1 do
    case func.() do
      {:ok, result} ->
        {:ok, result}

      {:error, reason} ->
        delay = calculate_delay(base_delay_ms, attempt_num)

        Logger.warning(
          "ReqLLM provider: Retryable error on attempt #{attempt_num}, " <>
            "retrying in #{delay}ms. Reason: #{inspect(reason)}"
        )

        Process.sleep(delay)
        with_retry(func, attempts_left - 1, base_delay_ms, attempt_num + 1)
    end
  end

  defp calculate_delay(base_delay_ms, attempt_num) do
    exponential_delay = base_delay_ms * :math.pow(2, attempt_num - 1)
    jitter = :rand.uniform(round(exponential_delay * 0.1))
    round(exponential_delay + jitter)
  end

  defp available_models do
    [
      "anthropic:claude-3-5-sonnet",
      "anthropic:claude-3-opus",
      "anthropic:claude-3-haiku",
      "openai:gpt-4",
      "openai:gpt-4-turbo",
      "openai:gpt-3.5-turbo"
    ]
  end
end
