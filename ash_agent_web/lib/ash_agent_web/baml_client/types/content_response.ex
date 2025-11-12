defmodule AshAgentWeb.BamlClient.Types.ContentResponse do
  use Ash.TypedStruct

  @moduledoc """
  Generated from BAML class: ContentResponse
  Source: baml_src/...

  This struct is automatically generated from BAML schema definitions.
  Do not edit directly - modify the BAML file and regenerate.
  """

  typed_struct do
    field(:content, :string, allow_nil?: false)
  end
end