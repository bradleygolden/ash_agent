defmodule AshAgent.Test.Reply do
  @moduledoc false
  use Ash.TypedStruct

  typed_struct do
    field :content, :string, allow_nil?: false
    field :confidence, :float
  end
end
