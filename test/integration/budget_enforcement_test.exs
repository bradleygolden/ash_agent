defmodule AshAgent.BudgetEnforcementTest do
  use ExUnit.Case, async: true
  @moduletag :integration

  alias AshAgent.{Error, Info}
  alias AshAgent.Test.TestDomain

  defmodule AgentWithBudgetHalt do
    use Ash.Resource,
      domain: TestDomain,
      extensions: [AshAgent.Resource]

    agent do
      provider :mock
      client "mock:test"
      token_budget(1000)
      budget_strategy(:halt)
      input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
      output_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
      instruction("Test: {{ message }}")
    end

    attributes do
      uuid_primary_key :id
    end
  end

  defmodule AgentWithBudgetWarn do
    use Ash.Resource,
      domain: TestDomain,
      extensions: [AshAgent.Resource]

    agent do
      provider :mock
      client "mock:test"
      token_budget(1000)
      budget_strategy(:warn)
      input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
      output_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
      instruction("Test: {{ message }}")
    end

    attributes do
      uuid_primary_key :id
    end
  end

  defmodule AgentWithoutBudget do
    use Ash.Resource,
      domain: TestDomain,
      extensions: [AshAgent.Resource]

    agent do
      provider :mock
      client "mock:test"
      input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
      output_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
      instruction("Test: {{ message }}")
    end

    attributes do
      uuid_primary_key :id
    end
  end

  describe "Info.token_budget/1" do
    test "returns configured budget" do
      assert Info.token_budget(AgentWithBudgetHalt) == 1000
    end

    test "returns nil when no budget configured" do
      assert Info.token_budget(AgentWithoutBudget) == nil
    end
  end

  describe "Info.budget_strategy/1" do
    test "returns configured halt strategy" do
      assert Info.budget_strategy(AgentWithBudgetHalt) == :halt
    end

    test "returns configured warn strategy" do
      assert Info.budget_strategy(AgentWithBudgetWarn) == :warn
    end

    test "returns default warn strategy when not configured" do
      assert Info.budget_strategy(AgentWithoutBudget) == :warn
    end
  end

  describe "Error.budget_error/2" do
    test "creates budget error with details" do
      error =
        Error.budget_error("Token budget (1000) exceeded", %{
          token_budget: 1000,
          cumulative_tokens: 1500,
          exceeded_by: 500
        })

      assert error.type == :budget_error
      assert error.message == "Token budget (1000) exceeded"
      assert error.details.token_budget == 1000
      assert error.details.cumulative_tokens == 1500
      assert error.details.exceeded_by == 500
    end
  end

  describe "runtime execution with budgets" do
    test "agent with halt strategy executes successfully when under budget" do
      {:ok, result} = AshAgent.Runtime.call(AgentWithBudgetHalt, %{message: "test"})
      assert %AshAgent.Result{output: %{message: _}} = result
    end

    test "agent with warn strategy executes successfully when under budget" do
      {:ok, result} = AshAgent.Runtime.call(AgentWithBudgetWarn, %{message: "test"})
      assert %AshAgent.Result{output: %{message: _}} = result
    end

    test "agent without budget executes successfully" do
      {:ok, result} = AshAgent.Runtime.call(AgentWithoutBudget, %{message: "test"})
      assert %AshAgent.Result{output: %{message: _}} = result
    end

    test "agent with halt strategy has correct configuration" do
      assert Info.token_budget(AgentWithBudgetHalt) == 1000
      assert Info.budget_strategy(AgentWithBudgetHalt) == :halt
    end

    test "agent with warn strategy has correct configuration" do
      assert Info.token_budget(AgentWithBudgetWarn) == 1000
      assert Info.budget_strategy(AgentWithBudgetWarn) == :warn
    end

    test "agent without budget has nil configuration" do
      assert Info.token_budget(AgentWithoutBudget) == nil
      assert Info.budget_strategy(AgentWithoutBudget) == :warn
    end
  end
end
