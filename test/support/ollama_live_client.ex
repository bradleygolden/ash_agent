defmodule AshAgent.Test.OllamaLiveClient do
  @moduledoc false
  @baml_src Path.expand("ollama_live_baml/baml_src", __DIR__)

  use BamlElixir.Client, path: "test/support/ollama_live_baml/baml_src"

  def __baml_src_path__, do: @baml_src
end
