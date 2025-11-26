defmodule AshAgent.Runtime.Hooks do
  @moduledoc """
  Hook system for extending AshAgent runtime behavior.

  Hooks allow you to inject custom behavior at key points in the agent execution lifecycle.
  This is useful for logging, monitoring, modifying inputs/outputs, and implementing
  custom retry logic.

  ## Available Hooks

  1. **before_call** - Called before rendering the prompt or calling the LLM
  2. **after_render** - Called after prompt rendering, before LLM call
  3. **after_call** - Called after successful LLM response
  4. **on_error** - Called when any error occurs

  ## Implementing Hooks

  Create a module that implements the `AshAgent.Runtime.Hooks` behaviour:

      defmodule MyApp.AgentHooks do
        @behaviour AshAgent.Runtime.Hooks

        @impl true
        def before_call(ctx) do
          IO.puts("Starting agent call...")
          {:ok, ctx}
        end

        @impl true
        def after_call(ctx) do
          IO.puts("Agent call completed!")
          {:ok, ctx}
        end

        @impl true
        def on_error(ctx) do
          Logger.error("Agent error: \#{inspect(ctx.error)}")
          {:ok, ctx}
        end
      end

  Then register the hooks in your agent configuration:

      agent do
        client "anthropic:claude-sonnet-4-20250514"
        output MyOutput
        prompt "..."
        hooks MyApp.AgentHooks
      end

  ## Hook Context

  Each hook receives a context map with:

  - `:agent` - The agent module
  - `:input` - The input arguments
  - `:rendered_prompt` - The rendered prompt (available after `after_render`)
  - `:response` - The LLM response (available in `after_call`)
  - `:error` - The error (available in `on_error`)

  ## Error Handling

  All hooks should return `{:ok, context}` or `{:error, reason}`.
  If a hook returns an error, it will abort the agent execution.
  """

  @type hook_context :: %{
          agent: module(),
          input: map(),
          rendered_prompt: String.t() | nil,
          response: struct() | nil,
          error: term() | nil
        }

  @callback before_call(hook_context()) :: {:ok, hook_context()} | {:error, term()}
  @callback after_render(hook_context()) :: {:ok, hook_context()} | {:error, term()}
  @callback after_call(hook_context()) :: {:ok, hook_context()} | {:error, term()}
  @callback on_error(hook_context()) :: {:ok, hook_context()} | {:error, term()}

  @optional_callbacks [
    before_call: 1,
    after_render: 1,
    after_call: 1,
    on_error: 1
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
