defmodule AshAgent.Transformers.InjectExtensionConfig do
  @moduledoc """
  Injects client and provider configuration from module attributes into DSL.

  This transformer enables dynamic module generation by allowing client/provider
  to be specified as module attributes rather than DSL macros.

  When a module is created with @ash_agent_client and @ash_agent_provider attributes,
  this transformer reads them and sets the corresponding DSL options.
  """
  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @impl true
  def before?(AshAgent.Transformers.ValidateAgent), do: true
  def before?(AshAgent.Transformers.AddContextAttribute), do: true
  def before?(AshAgent.Transformers.AddAgentActions), do: true
  def before?(_), do: false

  @impl true
  def after?(_), do: false

  @impl true
  def transform(dsl_state) do
    module = Transformer.get_persisted(dsl_state, :module)

    dsl_state =
      case Module.get_attribute(module, :ash_agent_client) do
        nil -> dsl_state
        client -> Transformer.set_option(dsl_state, [:agent], :client, client)
      end

    dsl_state =
      case Module.get_attribute(module, :ash_agent_provider) do
        nil -> dsl_state
        provider -> Transformer.set_option(dsl_state, [:agent], :provider, provider)
      end

    {:ok, dsl_state}
  end
end
