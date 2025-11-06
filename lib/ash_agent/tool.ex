defmodule AshAgent.Tool do
  @moduledoc """
  Behavior for AshAgent tools that can be called by LLM agents.

  Tools represent functions that agents can invoke during execution.
  Each tool must provide a schema (for LLM understanding) and an
  execution function.
  """

  @type parameter_schema :: %{
          type: :string | :integer | :number | :boolean | :object | :array,
          required: boolean(),
          description: String.t(),
          properties: map(),
          items: map()
        }

  @type schema :: %{
          name: String.t(),
          description: String.t(),
          parameters: %{
            type: :object,
            properties: %{atom() => parameter_schema()},
            required: [atom()]
          }
        }

  @type execution_result :: {:ok, map()} | {:error, term()}

  @type context :: %{
          agent: module(),
          domain: module(),
          actor: term(),
          tenant: term()
        }

  @callback name() :: atom()
  @callback description() :: String.t()
  @callback schema() :: schema()
  @callback execute(args :: map(), context :: context()) :: execution_result()

  @doc """
  Validates that a module implements the Tool behavior correctly.
  """
  def validate_implementation!(module) do
    unless function_exported?(module, :name, 0) do
      raise ArgumentError, "Tool #{inspect(module)} must implement name/0"
    end

    unless function_exported?(module, :description, 0) do
      raise ArgumentError, "Tool #{inspect(module)} must implement description/0"
    end

    unless function_exported?(module, :schema, 0) do
      raise ArgumentError, "Tool #{inspect(module)} must implement schema/0"
    end

    unless function_exported?(module, :execute, 2) do
      raise ArgumentError, "Tool #{inspect(module)} must implement execute/2"
    end

    :ok
  end

  @doc """
  Maps parameter types to JSON Schema types per JSON Schema Draft 7.
  """
  def map_type_to_json_schema(:string), do: "string"
  def map_type_to_json_schema(:integer), do: "integer"
  def map_type_to_json_schema(:float), do: "number"
  def map_type_to_json_schema(:number), do: "number"
  def map_type_to_json_schema(:boolean), do: "boolean"
  def map_type_to_json_schema(:uuid), do: "string"
  def map_type_to_json_schema(:map), do: "object"
  def map_type_to_json_schema(:atom), do: "string"
  def map_type_to_json_schema({:array, _item_type}), do: "array"
  def map_type_to_json_schema(_unknown), do: "string"

  @doc """
  Builds a JSON Schema property definition from a parameter spec.
  """
  def build_property_schema(parameter) when is_map(parameter) do
    base_schema = %{
      "type" => map_type_to_json_schema(parameter[:type])
    }

    case parameter[:description] do
      nil -> base_schema
      "" -> base_schema
      description -> Map.put(base_schema, "description", description)
    end
  end

  @doc """
  Builds the properties object for JSON Schema from parameter list.
  """
  def build_properties(parameters) when is_list(parameters) do
    parameters
    |> Enum.map(fn param ->
      name = to_string(param[:name])
      schema = build_property_schema(param)
      {name, schema}
    end)
    |> Map.new()
  end

  def build_properties([]), do: %{}
  def build_properties(nil), do: %{}

  @doc """
  Extracts required field names from parameters.
  Returns a list of string names for JSON Schema required array.
  """
  def extract_required_fields(parameters) when is_list(parameters) do
    parameters
    |> Enum.filter(fn param -> param[:required] == true end)
    |> Enum.map(fn param -> to_string(param[:name]) end)
  end

  def extract_required_fields([]), do: []
  def extract_required_fields(nil), do: []

  @doc """
  Builds a complete JSON Schema for tool parameters per JSON Schema Draft 7.

  ## Parameters
    - name: Tool name
    - description: Tool description
    - parameters: List of parameter specs

  ## Returns
  Complete JSON Schema map with string keys.
  """
  def build_tool_json_schema(name, description, parameters) do
    %{
      "name" => to_string(name),
      "description" => description || "",
      "parameters" => %{
        "type" => "object",
        "properties" => build_properties(parameters),
        "required" => extract_required_fields(parameters)
      }
    }
  end

  @doc """
  Builds a JSON Schema compatible tool schema from a tool module or instance.

  If given a tool instance (struct), checks if the module implements `to_schema/1`
  and uses that for instance-based schema generation. Otherwise falls back to
  the module-level `schema/0` callback.

  If given a module atom, calls the module-level `schema/0` callback directly.
  """
  def to_json_schema(%module{} = tool_instance) do
    if function_exported?(module, :to_schema, 1) do
      module.to_schema(tool_instance)
    else
      module.schema()
    end
  end

  def to_json_schema(module) when is_atom(module) do
    module.schema()
  end
end
