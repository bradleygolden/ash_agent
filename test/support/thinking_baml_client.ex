defmodule AshAgent.Test.ThinkingBamlClient do
  @moduledoc false
  @baml_src Path.expand("thinking_baml/baml_src", __DIR__)

  use BamlElixir.Client, path: "test/support/thinking_baml/baml_src"

  def __baml_src_path__, do: @baml_src
end
