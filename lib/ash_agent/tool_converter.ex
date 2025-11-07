defmodule AshAgent.ToolConverter do
  @moduledoc """
  Converts AshAgent tool definitions to provider-specific formats.

  Handles conversion to JSON Schema (for ReqLLM) and other provider formats.
  """

  alias AshAgent.{Tool, Tools.AshAction, Tools.Function}

  @doc """
  Converts a list of tool definitions to JSON Schema format for ReqLLM.
  """
  @spec to_json_schema([map()]) :: [map()]
  def to_json_schema(tool_definitions) do
    Enum.map(tool_definitions, &tool_to_json_schema/1)
  end

  defp tool_to_json_schema(%{name: name, description: description, parameters: parameters}) do
    Tool.build_tool_json_schema(name, description, normalize_parameters(parameters))
  end

  defp normalize_parameters(nil), do: []
  defp normalize_parameters([]), do: []
  defp normalize_parameters(params) when is_list(params) do
    Enum.map(params, fn
      {name, spec} when is_list(spec) ->
        {name, spec}

      param when is_map(param) ->
        {param[:name] || param["name"], Map.to_list(param)}
    end)
  end
end

