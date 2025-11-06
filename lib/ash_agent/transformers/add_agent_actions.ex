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
    output_type = Transformer.get_option(dsl_state, [:agent], :output)
    input_args = get_input_arguments(dsl_state)

    action = build_action_spec(action_name, output_type, input_args)
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

  defp build_action_spec(:call, output_type, input_args) do
    %Ash.Resource.Actions.Action{
      name: :call,
      type: :action,
      description: "Call the agent and return a structured response",
      arguments: input_args,
      returns: output_type,
      run: {AshAgent.Actions.Call, []},
      primary?: false
    }
  end

  defp build_action_spec(:stream, output_type, input_args) do
    stream_type = if output_type, do: {:array, output_type}, else: {:array, :any}

    %Ash.Resource.Actions.Action{
      name: :stream,
      type: :action,
      description: "Stream partial responses from the agent",
      arguments: input_args,
      returns: stream_type,
      run: {AshAgent.Actions.Stream, []},
      primary?: false
    }
  end

  defp get_input_arguments(dsl_state) do
    dsl_state
    |> Transformer.get_entities([:agent, :input])
    |> Enum.map(&build_action_argument/1)
  end

  defp build_action_argument(arg) do
    %Ash.Resource.Actions.Argument{
      name: arg.name,
      type: arg.type,
      allow_nil?: Map.get(arg, :allow_nil?, true),
      default: Map.get(arg, :default),
      description: Map.get(arg, :doc),
      public?: true,
      constraints: []
    }
  end
end
