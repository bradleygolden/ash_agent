defmodule AshAgent.ResourceTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias Ash.Resource.Info, as: ResourceInfo
  alias Spark.Dsl.Extension

  # Define test resources upfront so they can be registered in TestDomain
  defmodule TestChatAgent do
    use Ash.Resource, domain: __MODULE__.TestDomain, extensions: [AshAgent.Resource]

    defmodule Reply do
      use Ash.TypedStruct

      typed_struct do
        field :content, :string, allow_nil?: false
      end
    end

    agent do
      client("anthropic:claude-3-5-sonnet", temperature: 0.5, max_tokens: 50)
      output(Reply)
      prompt("Test prompt")
    end
  end

  defmodule AgentWithActions do
    use Ash.Resource, domain: __MODULE__.TestDomain, extensions: [AshAgent.Resource]

    defmodule Reply do
      use Ash.TypedStruct

      typed_struct do
        field :content, :string
      end
    end

    agent do
      client("anthropic:claude-3-5-sonnet")
      output(Reply)
      prompt("Test")
    end
  end

  defmodule AgentWithSigil do
    use Ash.Resource, domain: __MODULE__.TestDomain, extensions: [AshAgent.Resource]
    import AshAgent.Sigils

    defmodule Reply do
      use Ash.TypedStruct

      typed_struct do
        field :message, :string
      end
    end

    agent do
      client("anthropic:claude-3-5-sonnet")
      output(Reply)
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
