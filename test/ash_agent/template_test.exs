defmodule AshAgent.TemplateTest do
  use ExUnit.Case, async: true

  defmodule Output do
    use Ash.TypedStruct

    typed_struct do
      field :headline, :string, allow_nil?: false
    end
  end

  defmodule SimpleTemplate do
    use AshAgent.Template

    agent do
      output AshAgent.TemplateTest.Output

      input do
        argument :title, :string, allow_nil?: false
        argument :max_words, :integer, default: 10
      end

      prompt ~p"Summarize: {{ title }} (max {{ max_words }} words)"
    end
  end

  defmodule TemplateWithBudget do
    use AshAgent.Template

    agent do
      output AshAgent.TemplateTest.Output
      token_budget(10_000)
      budget_strategy(:halt)

      input do
        argument :text, :string, allow_nil?: false, doc: "The text to process"
        argument :sensitive_data, :string, sensitive?: true
      end

      prompt ~p"Process: {{ text }}"
    end
  end

  describe "AshAgent.Template" do
    test "template modules compile successfully" do
      assert Code.ensure_loaded?(SimpleTemplate)
      assert Code.ensure_loaded?(TemplateWithBudget)
    end

    test "templates expose Spark fragment DSL state" do
      assert function_exported?(SimpleTemplate, :spark_dsl_config, 0)
    end
  end
end
