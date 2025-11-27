defmodule AshAgent.Test.ThinkingBamlClient.Types.MathAnswer do
  use Ash.TypedStruct

  @moduledoc """
  Generated from BAML class: MathAnswer
  Source: baml_src/...

  This struct is automatically generated from BAML schema definitions.
  Do not edit directly - modify the BAML file and regenerate.
  """

  typed_struct do
    field(:answer, :integer, allow_nil?: false)
    field(:explanation, :string, allow_nil?: false)
  end
end
