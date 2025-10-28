defmodule AshAgent.Info do
  @moduledoc """
  Introspection functions for AshAgent extensions.

  This module provides functions to retrieve configuration from resources and domains
  that use the AshAgent extensions.

  ## Usage

  ```elixir
  # Check if agent is enabled on a resource
  AshAgent.Info.agent_enabled?(MyApp.MyAgent)

  # Get domain-level configuration
  AshAgent.Info.domain_default_enabled?(MyApp.Domain)
  ```
  """

  use Spark.InfoGenerator, extension: AshAgent.Resource, sections: [:agent]

  alias Spark.Dsl.Extension

  @doc """
  Returns whether agent functionality is enabled for the given resource.

  ## Examples

      iex> AshAgent.Info.agent_enabled?(MyApp.MyAgent)
      true
  """
  @spec agent_enabled?(Spark.Dsl.t()) :: boolean()
  def agent_enabled?(resource) do
    Extension.get_opt(resource, [:agent], :enabled, true)
  end

  @doc """
  Returns the default enabled value for agents in the given domain.

  ## Examples

      iex> AshAgent.Info.domain_default_enabled?(MyApp.Domain)
      true
  """
  @spec domain_default_enabled?(Spark.Dsl.t()) :: boolean()
  def domain_default_enabled?(domain) do
    Extension.get_opt(domain, [:agent], :default_enabled, true)
  end
end
