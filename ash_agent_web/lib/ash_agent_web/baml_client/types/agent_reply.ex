defmodule AshAgentWeb.BamlClient.Types.AgentReply do
  use Ash.TypedStruct

  @moduledoc """
  Generated from BAML class: AgentReply
  Source: baml_src/...

  This struct is automatically generated from BAML schema definitions.
  Do not edit directly - modify the BAML file and regenerate.
  """

  typed_struct do
    field(:confidence, :float, allow_nil?: false)
    field(:content, :string, allow_nil?: false)
  end
end