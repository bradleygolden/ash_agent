defmodule AshAgent.InfoTest do
  use ExUnit.Case, async: false

  alias AshAgent.Info
  alias AshAgent.RuntimeRegistry
  alias AshAgent.Test.TestAgents

  setup do
    RuntimeRegistry.register_context_module(AshAgent.Context)
    :ok
  end

  describe "provider/1" do
    test "returns default :req_llm for agent without explicit provider" do
      assert Info.provider(TestAgents.MinimalAgent) == :req_llm
    end
  end

  describe "token_budget/1" do
    test "returns nil for agent without token budget" do
      assert Info.token_budget(TestAgents.MinimalAgent) == nil
    end
  end

  describe "budget_strategy/1" do
    test "returns default :warn for agent without explicit strategy" do
      assert Info.budget_strategy(TestAgents.MinimalAgent) == :warn
    end
  end

  describe "agent_config/1" do
    test "returns complete configuration map for minimal agent" do
      config = Info.agent_config(TestAgents.MinimalAgent)

      assert is_map(config)
      assert config.client == "anthropic:claude-3-5-sonnet"
      assert config.client_opts == []
      assert config.provider == :req_llm
      assert config.prompt == "Simple test"
      assert config.output_type == TestAgents.SimpleOutput
      assert config.hooks == []
      assert config.input_args == []
      assert config.token_budget == nil
      assert config.budget_strategy == :warn
      assert config.context_module == AshAgent.Context
    end

    test "returns configuration with client options" do
      config = Info.agent_config(TestAgents.AgentWithClientOpts)

      assert config.client == "anthropic:claude-3-5-sonnet"
      assert config.client_opts == [temperature: 0.5, max_tokens: 200]
    end

    test "returns configuration with input arguments" do
      config = Info.agent_config(TestAgents.AgentWithArguments)

      assert length(config.input_args) == 1
      [arg] = config.input_args
      assert arg.name == :input
      assert arg.type == :string
    end

    test "returns configuration with multiple input arguments" do
      config = Info.agent_config(TestAgents.AgentWithMultipleArgs)

      assert length(config.input_args) == 2
      arg_names = Enum.map(config.input_args, & &1.name)
      assert :task in arg_names
      assert :priority in arg_names
    end

    test "returns complex output type" do
      config = Info.agent_config(TestAgents.AgentWithComplexOutput)

      assert config.output_type == TestAgents.ComplexOutput
    end

    test "profile is nil by default" do
      config = Info.agent_config(TestAgents.MinimalAgent)

      assert config.profile == nil
    end
  end

  describe "agent config with custom budget settings" do
    defmodule BudgetedOutput do
      use Ash.TypedStruct

      typed_struct do
        field :result, :string
      end
    end

    defmodule AgentWithBudget do
      use Ash.Resource,
        domain: AshAgent.TestDomain,
        extensions: [AshAgent.Resource]

      resource do
        require_primary_key? false
      end

      agent do
        client "anthropic:claude-3-5-sonnet"
        output BudgetedOutput
        prompt "Test"
        token_budget(10_000)
        budget_strategy(:halt)
      end
    end

    test "returns token budget when configured" do
      assert Info.token_budget(AgentWithBudget) == 10_000
    end

    test "returns budget strategy when configured" do
      assert Info.budget_strategy(AgentWithBudget) == :halt
    end

    test "agent_config includes budget settings" do
      config = Info.agent_config(AgentWithBudget)

      assert config.token_budget == 10_000
      assert config.budget_strategy == :halt
    end
  end
end
