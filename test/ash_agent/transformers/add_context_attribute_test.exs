defmodule AshAgent.Transformers.AddContextAttributeTest do
  use ExUnit.Case, async: true

  import AshAgent.Sigils

  alias Ash.Resource.Attribute
  alias Ash.Resource.Info

  defmodule TestOutput do
    use Ash.TypedStruct

    typed_struct do
      field :response, :string
    end
  end

  defmodule MinimalAgent do
    use Ash.Resource,
      domain: AshAgent.TestDomain,
      extensions: [AshAgent.Resource]

    agent do
      client "anthropic:claude-3-5-sonnet"
      output TestOutput

      input do
        argument :message, :string
      end

      prompt ~p"""
      Test prompt
      """
    end
  end

  defmodule NonAgentResource do
    use Ash.Resource,
      domain: AshAgent.TestDomain

    attributes do
      uuid_primary_key :id
    end
  end

  defmodule AgentWithExistingContext do
    use Ash.Resource,
      domain: AshAgent.TestDomain,
      extensions: [AshAgent.Resource]

    import AshAgent.Sigils

    attributes do
      attribute :context, :string, allow_nil?: true, public?: true
    end

    agent do
      client "anthropic:claude-3-5-sonnet"
      output TestOutput

      input do
        argument :message, :string
      end

      prompt ~p"""
      Test prompt
      """
    end
  end

  describe "AddContextAttribute transformer" do
    test "adds context attribute to agent resources" do
      attribute = Info.attribute(MinimalAgent, :context)

      assert %Attribute{} = attribute
      assert attribute.name == :context
      assert attribute.type == AshAgent.Context
      assert attribute.allow_nil? == true
      assert attribute.default == nil
      assert attribute.public? == true
    end

    test "does not add context attribute to non-agent resources" do
      attribute = Info.attribute(NonAgentResource, :context)

      assert is_nil(attribute)
    end

    test "does not duplicate existing context attribute" do
      attribute = Info.attribute(AgentWithExistingContext, :context)

      assert %Attribute{} = attribute
      assert attribute.type == Ash.Type.String
    end
  end
end
