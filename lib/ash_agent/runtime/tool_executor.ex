defmodule AshAgent.Runtime.ToolExecutor do
  @moduledoc """
  Executes tools requested by LLM agents.

  Handles tool execution, validation, error handling, and result formatting.
  """

  alias AshAgent.{Tools.AshAction, Tools.Function}

  @doc """
  Executes a list of tool calls and returns results.

  Returns a list of tuples: `{tool_call_id, {:ok, result} | {:error, reason}}`
  """
  @spec execute_tools([map()], map(), map()) ::
          [{String.t(), {:ok, term()} | {:error, term()}}]
  def execute_tools(tool_calls, tool_definitions, runtime_context) do
    Enum.map(tool_calls, fn tool_call ->
      execute_tool(tool_call, tool_definitions, runtime_context)
    end)
  end

  defp execute_tool(%{id: id, name: name, arguments: args}, tool_definitions, runtime_context) do
    case find_tool(name, tool_definitions) do
      nil ->
        {id, {:error, "Tool #{inspect(name)} not found"}}

      tool_def ->
        context = build_context(runtime_context, tool_def)
        normalized_args = normalize_tool_args(args, tool_def)

        case execute_tool_impl(tool_def, normalized_args, context) do
          {:ok, result} ->
            {id, {:ok, result}}

          {:error, _reason} = error ->
            {id, error}
        end
    end
  end

  defp normalize_tool_args(args, tool_def) do
    parameters = Map.get(tool_def, :parameters, [])

    Enum.into(args, %{}, fn {key, value} ->
      key_atom = normalize_key(key)
      param_spec = Enum.find(parameters, fn p -> p[:name] == key_atom end)
      normalized_value = normalize_value(value, param_spec)

      {key_atom, normalized_value}
    end)
  rescue
    _ -> args
  end

  defp normalize_key(key) when is_binary(key), do: String.to_existing_atom(key)
  defp normalize_key(key), do: key

  defp normalize_value(value, %{type: :integer}) when is_binary(value) do
    case Integer.parse(value) do
      {int, _} -> int
      :error -> value
    end
  end

  defp normalize_value(value, %{type: :float}) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> value
    end
  end

  defp normalize_value(value, %{type: :boolean}) when is_binary(value) do
    case String.downcase(value) do
      "true" -> true
      "false" -> false
      _ -> value
    end
  end

  defp normalize_value(value, _param_spec), do: value

  defp find_tool(name, tool_definitions) when is_atom(name) do
    Enum.find(tool_definitions, fn tool ->
      tool_name = get_tool_name(tool)
      tool_name == name or to_string(tool_name) == to_string(name)
    end)
  end

  defp get_tool_name(%{name: name}), do: name
  defp get_tool_name(tool), do: Map.get(tool, :name)

  defp execute_tool_impl(%{action: {resource, action_name}} = tool_def, args, context) do
    tool = build_ash_action_tool(tool_def, resource, action_name)
    AshAction.execute(args, Map.put(context, :tool, tool))
  end

  defp execute_tool_impl(%{function: function} = tool_def, args, context) do
    tool = build_function_tool(tool_def, function)
    Function.execute(args, Map.put(context, :tool, tool))
  end

  defp execute_tool_impl(_tool_def, _args, _context) do
    {:error, "Tool must specify either :action or :function"}
  end

  defp build_ash_action_tool(tool_def, resource, action_name) do
    AshAction.new(
      name: tool_def.name,
      description: tool_def.description,
      resource: resource,
      action_name: action_name,
      parameters: normalize_parameters(tool_def.parameters)
    )
  end

  defp build_function_tool(tool_def, function) do
    Function.new(
      name: tool_def.name,
      description: tool_def.description,
      function: function,
      parameters: normalize_parameters(tool_def.parameters)
    )
  end

  defp normalize_parameters(nil), do: []
  defp normalize_parameters([]), do: []

  defp normalize_parameters(params) when is_list(params) do
    Enum.map(params, fn
      {name, spec} when is_list(spec) ->
        %{
          name: name,
          type: Keyword.get(spec, :type, :string),
          required: Keyword.get(spec, :required, false),
          description: Keyword.get(spec, :description)
        }

      param when is_map(param) ->
        param
    end)
  end

  defp build_context(runtime_context, _tool_def) do
    runtime_context
  end
end
