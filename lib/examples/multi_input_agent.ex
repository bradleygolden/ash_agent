defmodule Examples.MultiInputAgent do
  @moduledoc """
  A demonstration agent with multiple input types to showcase dynamic form rendering.
  """

  use Ash.Resource,
    domain: Examples.TestDomain,
    extensions: [AshAgent.Resource]

  import AshAgent.Sigils

  agent do
    client "anthropic:claude-3-5-sonnet"
    output :string
    prompt ~p"""
    Generate a {{ content_type }} about {{ topic }} with the following specifications:
    - Target audience: {{ audience }}
    - Word count: approximately {{ word_count }} words
    - Include examples: {{ include_examples }}
    """

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
