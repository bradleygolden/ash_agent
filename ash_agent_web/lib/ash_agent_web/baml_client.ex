defmodule AshAgentWeb.BamlClient do
  @moduledoc """
  BAML client for AshAgentWeb.
  """

  use BamlElixir.Client, path: "priv/baml_src"

  def __baml_src_path__ do
    Path.expand("priv/baml_src", File.cwd!())
  end
end
