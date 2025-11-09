defmodule AshAgent.Transformers.AddContextAttribute do
  @moduledoc """
  Automatically adds a `:context` attribute to agent resources.

  This transformer inspects the agent configuration and creates a context attribute
  that allows runtime state to be stored with agent instances.
  """

  use Spark.Dsl.Transformer

  alias Ash.Resource.Info
  alias Spark.Dsl.Transformer

  @extension Ash.Resource.Dsl

  @impl true
  def transform(dsl_state) do
    case Transformer.get_option(dsl_state, [:agent], :client) do
      nil ->
        {:ok, dsl_state}

      _client ->
        add_context_attribute(dsl_state)
    end
  end

  defp add_context_attribute(dsl_state) do
    if Info.attribute(dsl_state, :context) do
      {:ok, dsl_state}
    else
      {:ok, attribute} =
        Transformer.build_entity(@extension, [:attributes], :attribute,
          name: :context,
          type: AshAgent.Context,
          allow_nil?: true,
          default: nil,
          public?: true
        )

      {:ok, Transformer.add_entity(dsl_state, [:attributes], attribute)}
    end
  end
end
