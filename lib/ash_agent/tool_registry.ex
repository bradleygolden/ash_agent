defmodule AshAgent.ToolRegistry do
  @moduledoc """
  Registry for tools that can be shared across agents in a domain.

  The ToolRegistry provides a centralized place to register and retrieve tools
  that multiple agents within a domain can use. Tools can be registered at the
  domain level and then referenced by name in agent configurations.

  ## Example

      # Register a tool for a domain
      AshAgent.ToolRegistry.register_tool(
        MyApp.CustomerDomain,
        :get_customer,
        AshAgent.Tools.AshAction.new(
          name: :get_customer,
          description: "Get customer by ID",
          resource: MyApp.Customers.Customer,
          action_name: :read
        )
      )

      # Get a registered tool
      tool = AshAgent.ToolRegistry.get_tool(MyApp.CustomerDomain, :get_customer)

      # List all tools for a domain
      tools = AshAgent.ToolRegistry.list_tools(MyApp.CustomerDomain)
  """

  use Agent

  @doc """
  Starts the ToolRegistry agent.
  """
  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  @doc """
  Registers a tool for a specific domain.

  ## Parameters

  - `domain`: The domain module to register the tool under
  - `tool_name`: The name of the tool (atom)
  - `tool_impl`: The tool implementation struct

  ## Examples

      iex> AshAgent.ToolRegistry.register_tool(MyDomain, :my_tool, tool)
      :ok
  """
  def register_tool(domain, tool_name, tool_impl) do
    Agent.update(__MODULE__, fn registry ->
      domain_tools = Map.get(registry, domain, %{})
      updated_domain_tools = Map.put(domain_tools, tool_name, tool_impl)
      Map.put(registry, domain, updated_domain_tools)
    end)
  end

  @doc """
  Retrieves a tool by name for a specific domain.

  Returns `nil` if the tool is not found.

  ## Parameters

  - `domain`: The domain module to look up the tool in
  - `tool_name`: The name of the tool to retrieve

  ## Examples

      iex> AshAgent.ToolRegistry.get_tool(MyDomain, :my_tool)
      %AshAgent.Tools.Function{...}

      iex> AshAgent.ToolRegistry.get_tool(MyDomain, :nonexistent)
      nil
  """
  def get_tool(domain, tool_name) do
    Agent.get(__MODULE__, fn registry ->
      get_in(registry, [domain, tool_name])
    end)
  end

  @doc """
  Lists all tools registered for a specific domain.

  Returns a map of tool names to tool implementations.

  ## Parameters

  - `domain`: The domain module to list tools for

  ## Examples

      iex> AshAgent.ToolRegistry.list_tools(MyDomain)
      %{my_tool: %AshAgent.Tools.Function{...}}
  """
  def list_tools(domain) do
    Agent.get(__MODULE__, fn registry ->
      Map.get(registry, domain, %{})
    end)
  end

  @doc """
  Unregisters a tool from a specific domain.

  Returns `:ok` regardless of whether the tool existed.

  ## Parameters

  - `domain`: The domain module to unregister the tool from
  - `tool_name`: The name of the tool to unregister

  ## Examples

      iex> AshAgent.ToolRegistry.unregister_tool(MyDomain, :my_tool)
      :ok
  """
  def unregister_tool(domain, tool_name) do
    Agent.update(__MODULE__, fn registry ->
      domain_tools = Map.get(registry, domain, %{})
      updated_domain_tools = Map.delete(domain_tools, tool_name)

      if map_size(updated_domain_tools) == 0 do
        Map.delete(registry, domain)
      else
        Map.put(registry, domain, updated_domain_tools)
      end
    end)
  end

  @doc """
  Clears all tools for a specific domain.

  Returns `:ok`.

  ## Parameters

  - `domain`: The domain module to clear tools for

  ## Examples

      iex> AshAgent.ToolRegistry.clear_domain(MyDomain)
      :ok
  """
  def clear_domain(domain) do
    Agent.update(__MODULE__, fn registry ->
      Map.delete(registry, domain)
    end)
  end

  @doc """
  Clears all tools from the registry.

  Returns `:ok`.

  ## Examples

      iex> AshAgent.ToolRegistry.clear_all()
      :ok
  """
  def clear_all do
    Agent.update(__MODULE__, fn _registry -> %{} end)
  end
end
