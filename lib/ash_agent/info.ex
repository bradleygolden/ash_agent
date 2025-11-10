defmodule AshAgent.Info do
  @moduledoc """
  Introspection functions for AshAgent extensions.

  This module provides functions to retrieve configuration from resources and domains
  that use the AshAgent extensions.
  """

  use Spark.InfoGenerator, extension: AshAgent.Resource, sections: [:agent]

  alias Spark.Dsl.Extension

  @doc """
  Get the configured provider for an agent resource.

  Returns the provider option value, which can be:
  - An atom preset (`:req_llm`, `:mock`)
  - A custom module implementing `AshAgent.Provider`

  Defaults to `:req_llm` if not configured.

  ## Examples

      iex> AshAgent.Info.provider(MyAgent)
      :req_llm

      iex> AshAgent.Info.provider(MockAgent)
      :mock
  """
  @spec provider(Ash.Resource.t()) :: atom() | module()
  def provider(resource) do
    Extension.get_opt(resource, [:agent], :provider, :req_llm)
  end

  @doc """
  Returns all tool definitions for an agent.

  ## Examples

      iex> AshAgent.Info.tools(MyAgent)
      [%{name: :get_customer, ...}]
  """
  @spec tools(Ash.Resource.t()) :: [map()]
  def tools(resource) do
    Extension.get_entities(resource, [:tools])
  end

  @doc """
  Returns the tools section configuration for an agent.

  ## Examples

      iex> AshAgent.Info.tool_config(MyAgent)
      %{max_iterations: 5, timeout: 60_000, on_error: :continue}
  """
  @spec tool_config(Ash.Resource.t()) :: map()
  def tool_config(resource) do
    %{
      max_iterations: Extension.get_opt(resource, [:tools], :max_iterations, 5),
      timeout: Extension.get_opt(resource, [:tools], :timeout, 60_000),
      on_error: Extension.get_opt(resource, [:tools], :on_error, :continue)
    }
  end

  @doc """
  Get the configured token budget for an agent resource.

  Returns the maximum number of tokens allowed for agent execution,
  or nil if no budget is configured.

  ## Examples

      iex> AshAgent.Info.token_budget(MyAgent)
      10000

      iex> AshAgent.Info.token_budget(UnlimitedAgent)
      nil
  """
  @spec token_budget(Ash.Resource.t()) :: pos_integer() | nil
  def token_budget(resource) do
    Extension.get_opt(resource, [:agent], :token_budget, nil)
  end

  @doc """
  Get the configured budget strategy for an agent resource.

  Returns the strategy for handling token budget limits:
  - :halt - Stop execution and return error when limit exceeded
  - :warn - Emit warning but continue (default)

  ## Examples

      iex> AshAgent.Info.budget_strategy(MyAgent)
      :halt

      iex> AshAgent.Info.budget_strategy(DefaultAgent)
      :warn
  """
  @spec budget_strategy(Ash.Resource.t()) :: :halt | :warn
  def budget_strategy(resource) do
    Extension.get_opt(resource, [:agent], :budget_strategy, :warn)
  end
end
