defmodule AshAgent.Transformers.AddDomainInterfaces do
  @moduledoc false
  use Spark.Dsl.Transformer

  alias Ash.Domain.Info, as: DomainInfo
  alias Spark.Dsl.{Extension, Transformer}

  @impl true
  def transform(dsl_state) do
    if auto_define?(dsl_state) do
      add_interfaces_to_agent_resources(dsl_state)
    else
      {:ok, dsl_state}
    end
  end

  defp auto_define?(dsl_state) do
    Transformer.get_option(dsl_state, [:agent], :auto_define_interfaces?, true)
  end

  defp add_interfaces_to_agent_resources(dsl_state) do
    dsl_state
    |> DomainInfo.resource_references()
    |> Enum.reduce(dsl_state, fn reference, dsl_state ->
      if agent_resource?(reference.resource) do
        add_interfaces_for_agent(dsl_state, reference)
      else
        dsl_state
      end
    end)
    |> then(&{:ok, &1})
  end

  defp agent_resource?(resource) do
    AshAgent.Resource in Spark.extensions(resource)
  rescue
    _ -> false
  end

  defp add_interfaces_for_agent(dsl_state, reference) do
    input_args = get_input_args(reference.resource)
    suffix = derive_function_suffix(reference.resource)

    call_interface = build_interface(:call, suffix, input_args)
    stream_interface = build_interface(:stream, suffix, input_args)

    new_definitions =
      reference.definitions
      |> maybe_add_interface(call_interface)
      |> maybe_add_interface(stream_interface)

    new_reference = %{reference | definitions: new_definitions}
    Transformer.replace_entity(dsl_state, [:resources], new_reference, &(&1 == reference))
  end

  defp get_input_args(resource) do
    resource
    |> Extension.get_entities([:agent, :input])
    |> Enum.map(& &1.name)
  end

  defp derive_function_suffix(resource_module) do
    resource_module
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
  end

  defp build_interface(action_name, suffix, args) do
    %Ash.Resource.Interface{
      name: String.to_atom("#{action_name}_#{suffix}"),
      action: action_name,
      args: args,
      get?: false,
      require_reference?: false
    }
  end

  defp maybe_add_interface(definitions, interface) do
    if Enum.any?(definitions, &(&1.name == interface.name)) do
      definitions
    else
      definitions ++ [interface]
    end
  end
end
