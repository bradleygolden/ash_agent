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

  @doc """
  Get the input schema for an agent resource.

  Returns the Zoi schema for input validation, or nil if not configured.

  ## Examples

      iex> AshAgent.Info.input_schema(MyAgent)
      %Zoi.Object{...}
  """
  def input_schema(resource) do
    Extension.get_opt(resource, [:agent], :input_schema, nil, true)
  end

  @doc """
  Get the output schema for an agent resource.

  Returns the Zoi schema for output validation.

  ## Examples

      iex> AshAgent.Info.output_schema(MyAgent)
      %Zoi.Object{...}
  """
  def output_schema(resource) do
    Extension.get_opt(resource, [:agent], :output_schema, nil, true)
  end

  @doc """
  Get the complete agent configuration for a resource.

  Returns a map containing all agent configuration options. This is a convenience
  function for extensions that need to read multiple configuration values.

  ## Public Extension API

  This function is part of the stable public API for extensions like `ash_agent_tools`.
  Breaking changes will follow semantic versioning.

  ## Returns

  A map with the following keys:
  - `:client` - The client specification (string or tuple)
  - `:client_opts` - Additional client options
  - `:provider` - The provider module or preset
  - `:prompt` - The prompt template
  - `:input_schema` - The Zoi schema for input validation (optional)
  - `:output_schema` - The Zoi schema for output validation
  - `:hooks` - Hooks module configured for the agent
  - `:token_budget` - Token budget limit (if configured)
  - `:budget_strategy` - Budget enforcement strategy
  - `:context_module` - The context module from application config

  ## Examples

      iex> AshAgent.Info.agent_config(MyAgent)
      %{
        client: "anthropic:claude-3-5-sonnet",
        client_opts: [],
        provider: :req_llm,
        prompt: "You are a helpful assistant",
        input_schema: %Zoi.Object{...},
        output_schema: %Zoi.Object{...},
        hooks: nil,
        token_budget: nil,
        budget_strategy: :warn,
        context_module: AshAgent.Context
      }
  """
  @spec agent_config(Ash.Resource.t()) :: map()
  def agent_config(resource) do
    {client_string, client_opts} = Extension.get_opt(resource, [:agent], :client, nil, true)

    %{
      client: client_string,
      client_opts: client_opts,
      provider: Extension.get_opt(resource, [:agent], :provider, :req_llm),
      prompt: Extension.get_opt(resource, [:agent], :prompt, nil, true),
      input_schema: Extension.get_opt(resource, [:agent], :input_schema, nil, true),
      output_schema: Extension.get_opt(resource, [:agent], :output_schema, nil, true),
      hooks: Extension.get_opt(resource, [:agent], :hooks, nil, true),
      token_budget: Extension.get_opt(resource, [:agent], :token_budget, nil),
      budget_strategy: Extension.get_opt(resource, [:agent], :budget_strategy, :warn),
      context_module: AshAgent.Config.context_module(),
      profile: Extension.get_opt(resource, [:agent], :profile, nil)
    }
  end

  @doc """
  Check if automatic interface generation is enabled for a domain.

  Returns true if the domain will automatically generate code interface
  functions (`call_<resource_name>`, `stream_<resource_name>`) for all
  agent resources.

  Defaults to true if not explicitly configured.

  ## Examples

      iex> AshAgent.Info.auto_define_interfaces?(MyDomain)
      true
  """
  @spec auto_define_interfaces?(Ash.Domain.t()) :: boolean()
  def auto_define_interfaces?(domain) do
    Extension.get_opt(domain, [:agent], :auto_define_interfaces?, true)
  end
end
