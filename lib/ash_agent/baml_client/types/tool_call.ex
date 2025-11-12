defmodule AshAgent.BamlClient.Types.ToolCall do
  use Ash.TypedStruct

  @moduledoc """
  Generated from BAML class: ToolCall
  Source: baml_src/...

  This struct is automatically generated from BAML schema definitions.
  Do not edit directly - modify the BAML file and regenerate.
  """

  typed_struct do
    field(:tool_arguments, :map, allow_nil?: false)
    field(:tool_name, :string, allow_nil?: false)
  end
end