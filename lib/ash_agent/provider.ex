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
  @type schema :: map()
  @type opts :: keyword()
  @type response :: term()
  @type stream :: Enumerable.t()

  @doc """
  Execute a synchronous LLM call with structured output.

  ## Parameters

  - `client`: Provider-specific client configuration (opaque to AshAgent)
  - `prompt`: The fully rendered prompt text
  - `schema`: JSON schema for structured output
  - `opts`: Additional options (temperature, max_tokens, etc.)

  ## Returns

  - `{:ok, response}` - Successful response (provider-specific format)
  - `{:error, reason}` - Provider error

  ## Example

      iex> provider.call(client, "Hello", %{type: "object"}, temperature: 0.7)
      {:ok, %{"greeting" => "Hi there!"}}
  """
  @callback call(client, prompt, schema, opts) ::
              {:ok, response} | {:error, term()}

  @doc """
  Execute a streaming LLM call with structured output.

  ## Parameters

  Same as `call/4`

  ## Returns

  - `{:ok, stream}` - Stream of response chunks (Enumerable)
  - `{:error, reason}` - Provider error

  ## Example

      iex> {:ok, stream} = provider.stream(client, "Count", schema, [])
      iex> Enum.take(stream, 2)
      [%{delta: "1"}, %{delta: "2"}]
  """
  @callback stream(client, prompt, schema, opts) ::
              {:ok, stream} | {:error, term()}

  @doc """
  Optional: Introspect provider capabilities.

  Allows providers to expose available models, features, and constraints.
  Used for validation, documentation, and debugging.

  ## Returns

  Map with provider metadata:
  - `:provider` - Provider name (atom)
  - `:features` - List of supported features
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
