defmodule AshAgent.Transformers.AddAgentActions do
  @moduledoc """
  Automatically adds `:call` and `:stream` actions to agent resources.

  This transformer inspects the agent configuration and creates generic actions
  that can be used with Ash's code interface system, enabling actor-based
  authorization, domain integration, and policy enforcement.
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer
  alias Spark.Error.DslError

  @impl true
  def transform(dsl_state) do
    case Transformer.get_option(dsl_state, [:agent], :client) do
      nil ->
        {:ok, dsl_state}

      _client ->
        with {:ok, dsl_state} <- add_action(dsl_state, :call) do
          add_action(dsl_state, :stream)
        end
    end
  end

  defp add_action(dsl_state, action_name) do
    action = build_action_spec(action_name)
    dsl_state = Transformer.add_entity(dsl_state, [:actions], action)
    {:ok, dsl_state}
  rescue
    e ->
      {:error,
       DslError.exception(
         module: Transformer.get_persisted(dsl_state, :module),
         message: "Failed to add #{action_name} action: #{inspect(e)}",
         path: [:actions, action_name]
       )}
  end

  defp build_action_spec(:call) do
    %Ash.Resource.Actions.Action{
      name: :call,
      type: :action,
      description: "Call the agent and return a structured response",
      arguments: [context_argument()],
      returns: :map,
      run: {AshAgent.Actions.Call, []},
      primary?: false
    }
  end

  defp build_action_spec(:stream) do
    %Ash.Resource.Actions.Action{
      name: :stream,
      type: :action,
      description: "Stream partial responses from the agent",
      arguments: [context_argument()],
      returns: {:array, :map},
      run: {AshAgent.Actions.Stream, []},
      primary?: false
    }
  end

  defp context_argument do
    %Ash.Resource.Actions.Argument{
      name: :context,
      type: :struct,
      constraints: [instance_of: AshAgent.Context],
      allow_nil?: false,
      public?: true,
      description: "Context containing messages for the agent"
    }
  end
end
