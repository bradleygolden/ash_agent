defmodule AshAgent.Runtime.Hooks do
  @moduledoc """
  Hook system for extending AshAgent runtime behavior.

  Hooks allow you to inject custom behavior at key points in the agent execution lifecycle.
  This is useful for logging, monitoring, modifying inputs/outputs, implementing
  custom retry logic, and enabling Progressive Disclosure patterns.

  ## Hook Categories

  AshAgent provides two categories of hooks:

  ### Operation-Level Hooks (Original)

  These hooks operate at the high-level operation lifecycle (single LLM call):

  1. **before_call** - Called before rendering the prompt or calling the LLM
  2. **after_render** - Called after prompt rendering, before LLM call
  3. **after_call** - Called after successful LLM response
  4. **on_error** - Called when any error occurs

  ### Data-Level Hooks (Progressive Disclosure)

  These hooks enable Progressive Disclosure patterns by allowing data transformation
  and custom iteration control during tool-calling loops:

  5. **prepare_tool_results** - Process tool results before adding to context
     - Use for: Compacting large results, filtering sensitive data, summarization
     - Called after tools execute, before results added to context
     - Receives: tool calls, results, context, iteration number
     - Returns: Modified results or original on error

  6. **prepare_context** - Prepare context before converting to messages
     - Use for: Context compaction, removing old iterations, summarization
     - Called before context converted to messages for LLM
     - Receives: current context, token usage, iteration number
     - Returns: Modified context or original on error

  7. **prepare_messages** - Transform messages before LLM call
     - Use for: Message filtering, augmentation, formatting
     - Called after context converted to messages, before LLM call
     - Receives: messages, context, available tools, iteration number
     - Returns: Modified messages or original on error

  8. **on_iteration_start** - Hook called at iteration start
     - Use for: Custom stopping conditions, iteration initialization
     - Called at start of each tool-calling iteration
     - Receives: iteration number, context, max_iterations, client
     - Returns: {:ok, ctx} to continue, {:error, reason} to abort

  9. **on_iteration_complete** - Hook called after iteration completes
     - Use for: Iteration tracking, telemetry, side effects
     - Called after each iteration completes successfully or with error
     - Receives: iteration number, context, iteration result, token usage
     - Errors logged but don't fail iteration

  ## Error Handling

  Different hooks have different error handling semantics:

  - **prepare_*** hooks: Errors cause fallback to original data (logged as warnings)
  - **on_iteration_start**: Errors abort the iteration (stopping condition)
  - **on_iteration_complete**: Errors logged but iteration continues

  ## Default Behavior

  When no custom hooks are configured, `AshAgent.Runtime.DefaultHooks` runs automatically
  to maintain existing behavior (max iterations enforcement, token limit warnings).

  You can compose with default behavior in custom hooks:

      defmodule MyHooks do
        @behaviour AshAgent.Runtime.Hooks

        @impl true
        def on_iteration_start(ctx) do
          # Call default behavior first (max iterations check)
          with {:ok, ctx} <- AshAgent.Runtime.DefaultHooks.on_iteration_start(ctx) do
            # Add custom logic
            if my_custom_condition?(ctx) do
              {:error, AshAgent.Error.llm_error(message: "Custom stop")}
            else
              {:ok, ctx}
            end
          end
        end
      end

  ## Implementing Hooks

  Create a module that implements the `AshAgent.Runtime.Hooks` behaviour:

      defmodule MyApp.ProgressiveDisclosureHooks do
        @behaviour AshAgent.Runtime.Hooks

        @impl true
        def prepare_tool_results(ctx) do
          # Truncate large results to save tokens
          truncated = Enum.map(ctx.results, fn {name, result} ->
            case result do
              {:ok, data} when is_binary(data) ->
                {name, {:ok, String.slice(data, 0, 100)}}
              other ->
                {name, other}
            end
          end)
          {:ok, truncated}
        end

        @impl true
        def prepare_context(ctx) do
          # Keep only last 3 iterations
          compacted = AshAgent.Context.keep_last_iterations(ctx.context, 3)
          {:ok, compacted}
        end

        @impl true
        def on_iteration_start(ctx) do
          # Custom stopping condition: stop after 5 iterations
          if ctx.iteration_number >= 5 do
            {:error, AshAgent.Error.llm_error(message: "Reached 5 iterations")}
          else
            {:ok, ctx}
          end
        end
      end

  Then register the hooks in your agent configuration:

      agent do
        client "anthropic:claude-3-5-sonnet"
        output MyOutput
        prompt "..."
        hooks MyApp.ProgressiveDisclosureHooks
      end

  ## Hook Contexts

  Each hook receives a purpose-specific context map:

  ### tool_result_context
  - `:agent` - The agent module
  - `:iteration` - Current iteration number
  - `:tool_calls` - Tool calls made this iteration
  - `:results` - Tool execution results
  - `:context` - Current context
  - `:token_usage` - Token usage from LLM response

  ### context_preparation_context
  - `:agent` - The agent module
  - `:context` - Context to prepare
  - `:token_usage` - Accumulated token usage
  - `:iteration` - Current iteration number

  ### message_context
  - `:agent` - The agent module
  - `:context` - Current context
  - `:messages` - Messages to send to LLM
  - `:tools` - Available tools
  - `:iteration` - Current iteration number

  ### iteration_context
  - `:agent` - The agent module
  - `:iteration_number` - Current iteration number
  - `:context` - Current context
  - `:result` - Iteration result (nil for on_iteration_start)
  - `:token_usage` - Token usage from iteration
  - `:max_iterations` - Maximum allowed iterations
  - `:client` - LLM client identifier
  """

  @type hook_context :: %{
          agent: module(),
          input: map(),
          rendered_prompt: String.t() | nil,
          response: struct() | nil,
          error: term() | nil
        }

  @type tool_result_context :: %{
          agent: module(),
          iteration: integer(),
          tool_calls: [map()],
          results: [{String.t(), {:ok, term()} | {:error, term()}}],
          context: map(),
          token_usage: map() | nil
        }

  @type context_preparation_context :: %{
          agent: module(),
          context: map(),
          token_usage: map() | nil,
          iteration: integer()
        }

  @type message_context :: %{
          agent: module(),
          context: map(),
          messages: [map()],
          tools: [map()],
          iteration: integer()
        }

  @type iteration_context :: %{
          agent: module(),
          iteration_number: integer(),
          context: map(),
          result: term() | nil,
          token_usage: map() | nil,
          max_iterations: integer(),
          client: String.t()
        }

  @callback before_call(hook_context()) :: {:ok, hook_context()} | {:error, term()}
  @callback after_render(hook_context()) :: {:ok, hook_context()} | {:error, term()}
  @callback after_call(hook_context()) :: {:ok, hook_context()} | {:error, term()}
  @callback on_error(hook_context()) :: {:ok, hook_context()} | {:error, term()}

  @callback prepare_tool_results(tool_result_context()) :: {:ok, [term()]} | {:error, term()}
  @callback prepare_context(context_preparation_context()) ::
              {:ok, map()} | {:error, term()}
  @callback prepare_messages(message_context()) :: {:ok, [map()]} | {:error, term()}
  @callback on_iteration_start(iteration_context()) ::
              {:ok, iteration_context()} | {:error, term()}
  @callback on_iteration_complete(iteration_context()) ::
              {:ok, iteration_context()} | {:error, term()}

  @optional_callbacks [
    before_call: 1,
    after_render: 1,
    after_call: 1,
    on_error: 1,
    prepare_tool_results: 1,
    prepare_context: 1,
    prepare_messages: 1,
    on_iteration_start: 1,
    on_iteration_complete: 1
  ]

  @doc """
  Executes a hook callback if the hooks module is configured and implements the callback.

  Returns `{:ok, context}` if successful, or `{:error, reason}` if the hook fails.
  If no hooks are configured or the callback is not implemented, returns `{:ok, context}` unchanged.
  """
  def execute(hooks_module, _callback, context) when hooks_module in [nil, []],
    do: {:ok, context}

  def execute(hooks_module, callback, context) do
    if function_exported?(hooks_module, callback, 1) do
      apply(hooks_module, callback, [context])
    else
      {:ok, context}
    end
  end

  @doc """
  Creates an initial hook context from agent configuration and input arguments.
  """
  def build_context(agent_module, input_args) do
    %{
      agent: agent_module,
      input: ensure_map(input_args),
      rendered_prompt: nil,
      response: nil,
      error: nil
    }
  end

  @doc """
  Updates the hook context with a rendered prompt.
  """
  def with_prompt(context, prompt) do
    %{context | rendered_prompt: prompt}
  end

  @doc """
  Updates the hook context with a response.
  """
  def with_response(context, response) do
    %{context | response: response}
  end

  @doc """
  Updates the hook context with an error.
  """
  def with_error(context, error) do
    %{context | error: error}
  end

  defp ensure_map(args) when is_map(args), do: args
  defp ensure_map(args) when is_list(args), do: Map.new(args)
end
