defmodule AshAgent.SchemaConverter do
  @moduledoc """
  Converts TypedStruct definitions to req_llm schema format.

  Transforms TypedStruct modules into the keyword list format expected by
  ReqLLM.generate_object/4 and ReqLLM.stream_object/4.

  ## Schema Format

  req_llm expects schemas in this format:

      [
        name: [type: :string, required: true, doc: "Person's name"],
        age: [type: :pos_integer, required: true, doc: "Person's age"]
      ]

  This module reads TypedStruct field definitions and converts them to this format.

  ## Supported Types

  - Basic types: string, integer, float, boolean, map
  - Arrays: {:array, inner_type}
  - Nested arrays: {:array, {:array, inner_type}}
  - Objects: TypedStruct modules
  - Unions: Ash.Type.Union (converted to oneOf)
  - Custom types: Via callback mechanism

  ## Extension Point

  Custom types can be handled by implementing the `map_custom_type/1` callback
  in your module and configuring it via Application config:

      config :ash_agent, :custom_type_mapper, MyApp.CustomTypeMapper

  The callback should accept a type and return a req_llm schema type atom or tuple.
  """

  alias Ash.TypedStruct.Info, as: TypedStructInfo

  @doc """
  Converts a TypedStruct module to req_llm schema format.

  ## Parameters

    * `module` - A module that uses TypedStruct

  ## Returns

  A keyword list in req_llm schema format.

  ## Examples

      iex> defmodule Person do
      ...>   use TypedStruct
      ...>   typedstruct do
      ...>     field :name, String.t(), enforce: true
      ...>     field :age, integer()
      ...>   end
      ...> end
      iex> AshAgent.SchemaConverter.to_req_llm_schema(Person)
      [
        name: [type: :string, required: true],
        age: [type: :integer, required: false]
      ]

  """
  @spec to_req_llm_schema(module()) :: keyword()
  def to_req_llm_schema(module) do
    module
    |> TypedStructInfo.fields()
    |> Enum.map(&field_to_schema/1)
  rescue
    e in [ArgumentError, UndefinedFunctionError, FunctionClauseError] ->
      reraise ArgumentError,
              [
                message:
                  "Module #{inspect(module)} does not appear to be an Ash.TypedStruct. " <>
                    "Make sure it uses Ash.TypedStruct and defines fields. " <>
                    "Original error: #{Exception.message(e)}"
              ],
              __STACKTRACE__
  end

  defp field_to_schema(%Ash.TypedStruct.Field{} = field) do
    {field.name,
     [
       type: map_ash_type(field.type),
       required: field.allow_nil? == false && field.default == nil
     ]}
  end

  defp map_ash_type({:array, inner_type}), do: {:list, map_ash_type(inner_type)}

  defp map_ash_type({Ash.Type.Union, constraints}) do
    types = Keyword.get(constraints, :types, [])
    storage = Keyword.get(constraints, :storage, :type_and_value)

    case storage do
      :map_with_tag ->
        map_discriminated_union(types)

      :type_and_value ->
        map_simple_union(types)
    end
  end

  defp map_ash_type(Ash.Type.String), do: :string
  defp map_ash_type(Ash.Type.Integer), do: :integer
  defp map_ash_type(Ash.Type.Float), do: :float
  defp map_ash_type(Ash.Type.Boolean), do: :boolean
  defp map_ash_type(Ash.Type.Map), do: :map
  defp map_ash_type(Ash.Type.UtcDatetime), do: :string
  defp map_ash_type(Ash.Type.Date), do: :string
  defp map_ash_type(Ash.Type.Decimal), do: :float

  defp map_ash_type(:string), do: :string
  defp map_ash_type(:integer), do: :integer
  defp map_ash_type(:pos_integer), do: :pos_integer
  defp map_ash_type(:float), do: :float
  defp map_ash_type(:boolean), do: :boolean
  defp map_ash_type(:map), do: :map

  defp map_ash_type(module) when is_atom(module) do
    cond do
      function_exported?(module, :spark_is, 0) ->
        {:object, to_req_llm_schema(module)}

      custom_mapper = Application.get_env(:ash_agent, :custom_type_mapper) ->
        try do
          custom_mapper.map_custom_type(module)
        rescue
          _ -> :any
        end

      true ->
        :any
    end
  rescue
    _ -> :any
  end

  defp map_ash_type(_type), do: :any

  defp map_simple_union(types) do
    type_schemas =
      types
      |> Enum.map(fn {_name, config} ->
        map_ash_type(config[:type])
      end)

    {:one_of, type_schemas}
  end

  defp map_discriminated_union(types) do
    schemas =
      types
      |> Enum.map(fn {name, config} ->
        tag_field = config[:tag] || :type
        tag_value = config[:tag_value] || to_string(name)
        base_type = map_ash_type(config[:type])

        case base_type do
          {:object, fields} ->
            [{tag_field, [type: :string, required: true, enum: [tag_value]]} | fields]

          _other ->
            [
              {tag_field, [type: :string, required: true, enum: [tag_value]]},
              {:value, [type: base_type, required: true]}
            ]
        end
      end)

    {:one_of, schemas}
  end
end
