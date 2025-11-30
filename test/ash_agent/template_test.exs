defmodule AshAgent.TemplateTest do
  use ExUnit.Case, async: true

  defmodule SimpleTemplate do
    use AshAgent.Template

    agent do
      input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
      output_schema(Zoi.object(%{headline: Zoi.string()}, coerce: true))
      instruction(~p"Summarize: {{ title }} (max {{ max_words }} words)")
    end
  end

  defmodule TemplateWithBudget do
    use AshAgent.Template

    agent do
      input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
      output_schema(Zoi.object(%{headline: Zoi.string()}, coerce: true))
      token_budget(10_000)
      budget_strategy(:halt)
      instruction(~p"Process: {{ text }}")
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
