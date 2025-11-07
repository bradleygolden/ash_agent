defmodule AshAgent.Provider do
  @moduledoc """
  Behavior for LLM provider implementations.

  AshAgent is an **orchestration framework**, not an LLM execution layer.
  Providers handle the actual LLM communication while AshAgent handles
  agent workflows, state management, and coordination.

  ## Provider Responsibilities

  - Execute LLM calls (synchronous and streaming)
  - Handle provider-specific configuration
  - Parse provider responses into standard format
  - Report provider-specific errors

  ## AshAgent Responsibilities

  - Orchestrate agent workflows
  - Manage conversation state and memory
  - Handle tool execution and multi-turn interactions
  - Coordinate multi-agent systems
  - Provide observability and error recovery

  ## Implementing a Provider

  Providers must implement two required callbacks:

      defmodule MyApp.CustomProvider do
        @behaviour AshAgent.Provider

        @impl true
        def call(client, prompt, schema, opts) do
          # Execute synchronous LLM call
          {:ok, response} | {:error, reason}
        end

        @impl true
        def stream(client, prompt, schema, opts) do
          # Return enumerable stream
          {:ok, stream} | {:error, reason}
        end
      end

  ## Provider Configuration

  Providers are configured in the agent DSL:

      agent do
        provider :req_llm, client: "anthropic:claude-3-5-sonnet"
        # or
        provider MyApp.CustomProvider, api_key: "..."
      end
  """

  @type client :: term()
  @type prompt :: String.t()
  @type schema :: keyword()
  @type opts :: keyword()
  @type response :: term()
  @type stream :: Enumerable.t()
  @type capability :: :sync_call | :streaming | :tool_calling | :structured_output | atom()
  @type tools :: [map()] | nil
  @type messages :: [map()]
  @type context :: %{
          agent: module(),
          input: map(),
          rendered_prompt: String.t() | nil,
          response: term(),
          error: term()
        }

  @doc """
  Execute a synchronous LLM call with structured output.

  ## Parameters

  - `client`: Provider-specific client configuration (opaque to AshAgent)
  - `prompt`: The fully rendered prompt text (or nil if using messages)
  - `schema`: Schema definition (keyword list or provider-specific format)
  - `opts`: Additional options (temperature, max_tokens, etc.)
  - `context`: Execution context containing the agent module, raw input arguments,
    rendered prompt (if applicable), and hook metadata. Providers like ash_baml
    can use this to bypass prompt rendering and operate on structured inputs.
  - `tools`: List of tools in provider-specific format (JSON Schema for ReqLLM)
  - `messages`: List of messages for multi-turn conversations (if provided, prompt may be nil)

  ## Returns

  - `{:ok, response}` - Successful response (provider-specific format)
  - `{:error, reason}` - Provider error

  The response may contain tool calls that need to be executed. Providers should
  return tool calls in a standard format that the runtime can parse.

  ## Example

      iex> provider.call(client, "Hello", [name: [type: :string]], [], context, nil, nil)
      {:ok, %{"greeting" => "Hi there!"}}
  """
  @callback call(client, prompt, schema, opts, context, tools, messages) ::
              {:ok, response} | {:error, term()}

  @doc """
  Execute a streaming LLM call with structured output.

  ## Parameters

  Same as `call/7`

  ## Returns

  - `{:ok, stream}` - Stream of response chunks (Enumerable)
  - `{:error, reason}` - Provider error

  ## Example

      iex> {:ok, stream} = provider.stream(client, "Count", schema, [], context, nil, nil)
      iex> Enum.take(stream, 2)
      [%{delta: "1"}, %{delta: "2"}]
  """
  @callback stream(client, prompt, schema, opts, context, tools, messages) ::
              {:ok, stream} | {:error, term()}

  @doc """
  Optional: Introspect provider capabilities.

  Allows providers to expose available models, features, and constraints.
  Used for validation, documentation, and debugging.

  ## Returns

  Map with provider metadata:
  - `:provider` - Provider name (atom)
  - `:features` - List of supported features/capabilities
  - `:models` - List of available models (optional)
  - `:constraints` - Known limitations (optional)

  ## Example

      @impl true
      def introspect do
        %{
          provider: :req_llm,
          features: [:sync_call, :streaming, :structured_output, :function_calling],
          models: ["anthropic:claude-3-5-sonnet", "openai:gpt-4"],
          constraints: %{max_tokens: 200_000}
        }
      end
  """
  @callback introspect() :: map()
  @optional_callbacks [introspect: 0]
end
