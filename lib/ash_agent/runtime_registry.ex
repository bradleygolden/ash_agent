defmodule AshAgent.RuntimeRegistry do
  @moduledoc """
  Registry for runtime extension handlers.

  This allows packages like `ash_agent_tools` to register themselves as handlers
  for specific runtime capabilities (like tool calling), while keeping `ash_agent`
  independent and usable standalone.

  ## Architecture

  - `ash_agent` provides the base runtime and this registry
  - `ash_agent_tools` registers itself as the tool runtime handler on load
  - Users always call `AshAgent.Runtime.call()` regardless of which packages are installed
  - The runtime automatically delegates to the appropriate handler based on agent configuration

  ## Example

      # Extension packages register themselves during application startup
      AshAgent.RuntimeRegistry.register_tool_runtime(MyToolRuntime)

      # Users call the same function regardless of which extensions are installed
      AshAgent.Runtime.call(MyAgent, args)  # Works with or without extensions

  """

  use GenServer

  @registry_name __MODULE__

  ## Client API

  @doc """
  Starts the runtime registry.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: @registry_name)
  end

  @doc """
  Registers a module as the tool runtime handler.

  The handler module must implement:
  - `call/3` - Execute agent with tools
  - `stream/3` - Stream agent response with tools

  This is called by `ash_agent_tools` during application startup.
  """
  @spec register_tool_runtime(module()) :: :ok
  def register_tool_runtime(handler_module) do
    GenServer.call(@registry_name, {:register, :tool_runtime, handler_module})
  end

  @doc """
  Gets the registered tool runtime handler, if any.

  Returns `{:ok, module}` if a handler is registered, `:error` otherwise.
  """
  @spec get_tool_runtime() :: {:ok, module()} | :error
  def get_tool_runtime do
    case :ets.lookup(:ash_agent_runtime_registry, :tool_runtime) do
      [{:tool_runtime, handler}] -> {:ok, handler}
      [] -> :error
    end
  end

  @doc """
  Checks if a tool runtime handler is registered.
  """
  @spec has_tool_runtime?() :: boolean()
  def has_tool_runtime? do
    match?({:ok, _}, get_tool_runtime())
  end

  @doc """
  Registers a module as the context module handler.

  The context module should implement the same function signatures as `AshAgent.Context`
  (duck typing). Extension packages like `ash_agent_tools` register their context
  implementations during application startup to provide enhanced capabilities.

  ## Required Functions

  Context modules should implement:
  - `new(input, opts)` - Create new context
  - `to_messages(context)` - Convert to message format
  - `add_assistant_message(context, content, tool_calls)` - Add assistant message
  - `add_llm_call_timing(context)` - Track timing
  - `add_token_usage(context, usage)` - Track token usage
  - `get_cumulative_tokens(context)` - Get cumulative tokens
  - `exceeded_max_iterations?(context, max)` - Check iteration limit
  - `persist(context, attrs)` - Update context state

  ## Example

      AshAgent.RuntimeRegistry.register_context_module(MyExtension.Context)

  """
  @spec register_context_module(module()) :: :ok
  def register_context_module(context_module) do
    GenServer.call(@registry_name, {:register, :context_module, context_module})
  end

  @doc """
  Gets the registered context module, if any.

  Returns the registered context module if available, otherwise returns the default
  context module used by the agent runtime.
  """
  @spec get_context_module() :: module()
  def get_context_module do
    case :ets.lookup(:ash_agent_runtime_registry, :context_module) do
      [{:context_module, handler}] -> handler
      [] -> AshAgent.Context
    end
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    table =
      :ets.new(:ash_agent_runtime_registry, [
        :set,
        :public,
        :named_table,
        read_concurrency: true
      ])

    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:register, key, handler}, _from, state) do
    :ets.insert(:ash_agent_runtime_registry, {key, handler})
    {:reply, :ok, state}
  end
end
