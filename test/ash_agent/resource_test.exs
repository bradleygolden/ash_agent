defmodule AshAgent.ResourceTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Ash.Resource.Info, as: ResourceInfo
  alias Spark.Dsl.Extension

  defmodule TestChatAgent do
    use Ash.Resource, domain: __MODULE__.TestDomain, extensions: [AshAgent.Resource]

    resource do
      require_primary_key? false
    end

    agent do
      client("anthropic:claude-3-5-sonnet", temperature: 0.5, max_tokens: 50)
      output_schema(Zoi.object(%{content: Zoi.string()}, coerce: true))
      prompt("Test prompt")
    end
  end

  defmodule AgentWithActions do
    use Ash.Resource, domain: __MODULE__.TestDomain, extensions: [AshAgent.Resource]

    resource do
      require_primary_key? false
    end

    agent do
      client("anthropic:claude-3-5-sonnet")
      output_schema(Zoi.object(%{content: Zoi.string()}, coerce: true))
      prompt("Test")
    end
  end

  defmodule AgentWithSigil do
    use Ash.Resource, domain: __MODULE__.TestDomain, extensions: [AshAgent.Resource]
    import AshAgent.Sigils

    resource do
      require_primary_key? false
    end

    agent do
      client("anthropic:claude-3-5-sonnet")
      output_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
      prompt(~p"Hello {{ name }}")
    end
  end

  defmodule TestDomain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource AshAgent.ResourceTest.TestChatAgent
      resource AshAgent.ResourceTest.AgentWithActions
      resource AshAgent.ResourceTest.AgentWithSigil
    end
  end

  describe "AshAgent.Resource extension" do
    test "allows defining an agent with DSL" do
      assert Extension.get_opt(TestChatAgent, [:agent], :client) ==
               {"anthropic:claude-3-5-sonnet", [temperature: 0.5, max_tokens: 50]}
    end

    test "generates call and stream actions" do
      actions = ResourceInfo.actions(AgentWithActions)
      action_names = Enum.map(actions, & &1.name)

      assert :call in action_names
      assert :stream in action_names
    end

    test "imports sigil_p for prompts" do
      assert true
    end
  end
end
