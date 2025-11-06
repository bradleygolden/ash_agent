defmodule AshAgent.Runtime.Hooks do
  @moduledoc """
  Hook system for extending AshAgent runtime behavior.

  Hooks allow you to inject custom behavior at key points in the agent execution lifecycle.
  This is useful for logging, monitoring, modifying inputs/outputs, or implementing
  custom retry logic.

  ## Hook Lifecycle

  1. **before_call** - Called before rendering the prompt or calling the LLM
     - Can modify input arguments
     - Can abort execution by returning an error
     - Receives: agent module, input arguments

  2. **after_render** - Called after prompt rendering, before LLM call
     - Can modify the rendered prompt
     - Can inspect or log the prompt
     - Receives: agent module, input arguments, rendered prompt

  3. **after_call** - Called after successful LLM response
     - Can modify the response
     - Can perform logging or metrics collection
     - Receives: agent module, input arguments, rendered prompt, response

  4. **on_error** - Called when any error occurs
     - Can transform errors
     - Can implement retry logic
     - Receives: agent module, input arguments, error, context

  ## Implementing Hooks

  Create a module that implements the `AshAgent.Runtime.Hooks` behaviour:

      defmodule MyApp.AgentHooks do
        @behaviour AshAgent.Runtime.Hooks

        @impl true
        def before_call(context) do
          # Log the call
          Logger.info("Agent call: \#{inspect(context.agent)}")
          {:ok, context}
        end

        @impl true
        def after_render(context) do
          # Inspect the prompt
          IO.puts("Rendered prompt: \#{context.rendered_prompt}")
          {:ok, context}
        end

        @impl true
        def after_call(context) do
          # Log the response
          Logger.debug("Response: \#{inspect(context.response)}")
          {:ok, context}
        end

        @impl true
        def on_error(context) do
          # Log errors
          Logger.error("Agent error: \#{inspect(context.error)}")
          {:error, context.error}
        end
      end

  Then register the hooks in your agent configuration:

      agent do
        client "anthropic:claude-3-5-sonnet"
        output MyOutput
        prompt "..."
        hooks MyApp.AgentHooks
      end

  ## Hook Context

  The hook context is a map containing:
  - `:agent` - The agent module being called
  - `:input` - The input arguments (map)
  - `:rendered_prompt` - The rendered prompt (string, nil before rendering)
  - `:response` - The LLM response (struct, nil before response)
  - `:error` - The error that occurred (any, only in on_error)
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

  @optional_callbacks [before_call: 1, after_render: 1, after_call: 1, on_error: 1]

  @doc """
  Executes a hook callback if the hooks module is configured and implements the callback.

  Returns `{:ok, context}` if successful, or `{:error, reason}` if the hook fails.
  If no hooks are configured or the callback is not implemented, returns `{:ok, context}` unchanged.
  """
  def execute(nil, _callback, context), do: {:ok, context}

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
