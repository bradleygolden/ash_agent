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
end
