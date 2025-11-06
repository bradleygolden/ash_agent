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

  defp map_ash_type({:array, inner_type}), do: {:array, map_ash_type(inner_type)}

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
    if function_exported?(module, :spark_is, 0) do
      {:object, to_req_llm_schema(module)}
    else
      :any
    end
  rescue
    _ -> :any
  end

  defp map_ash_type(_type), do: :any
end
