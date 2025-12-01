defmodule AshAgent.Test.OpenAIBamlClient do
  @moduledoc false
  @baml_src Path.expand("openai_baml/baml_src", __DIR__)
  use BamlElixir.Client, path: "test/support/openai_baml/baml_src"

  def __baml_src_path__, do: @baml_src
end
