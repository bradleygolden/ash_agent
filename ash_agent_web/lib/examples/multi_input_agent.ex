defmodule Examples.MultiInputAgent do
  @moduledoc """
  A demonstration agent with multiple input types to showcase dynamic form rendering.
  """

  use Ash.Resource,
    domain: Examples.TestDomain,
    extensions: [AshAgent.Resource]

  resource do
    require_primary_key? false
  end

  agent do
    provider :baml
    client :default, function: :MultiInputAgent
    output AshAgentWeb.BamlClient.Types.ContentResponse

    input do
      argument :topic, :string, allow_nil?: false
      argument :content_type, :string, default: "summary"
      argument :audience, :string, default: "general public"
      argument :word_count, :integer, default: 100
      argument :include_examples, :boolean, default: true
    end
  end

  code_interface do
    define :call, args: [:topic, :content_type, :audience, :word_count, :include_examples]
  end
end
