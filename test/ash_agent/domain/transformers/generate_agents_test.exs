defmodule AshAgent.Domain.Transformers.GenerateAgentsTest do
  use ExUnit.Case, async: true

  alias Ash.Resource.Info, as: ResourceInfo
  alias Spark.Dsl.Extension

  defmodule SimpleTemplate do
    use AshAgent.Template

    agent do
      input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
      output_schema(Zoi.object(%{result: Zoi.string()}, coerce: true))
      instruction(~p"Echo: {{ message }}")
    end
  end

  defmodule TemplateWithMultipleArgs do
    use AshAgent.Template

    agent do
      input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
      output_schema(Zoi.object(%{result: Zoi.string()}, coerce: true))
      instruction(~p"Rewrite: {{ text }} in {{ style }} style")
    end
  end

  defmodule TestDomain do
    use Ash.Domain,
      extensions: [AshAgent.Domain],
      validate_config_inclusion?: false

    agents do
      agent(AshAgent.Domain.Transformers.GenerateAgentsTest.SimpleTemplate,
        client: "anthropic:claude-3-5-haiku"
      )

      agent(AshAgent.Domain.Transformers.GenerateAgentsTest.TemplateWithMultipleArgs,
        client: "openai:gpt-4o",
        as: :rewriter
      )
    end
  end

  describe "GenerateAgents transformer" do
    test "generates agent module from template" do
      assert Code.ensure_loaded?(TestDomain.SimpleTemplate)
    end

    test "uses custom name when :as option provided" do
      assert Code.ensure_loaded?(TestDomain.Rewriter)
    end

    test "generated module has AshAgent.Resource extension" do
      extensions = Spark.extensions(TestDomain.SimpleTemplate)
      assert AshAgent.Resource in extensions
    end

    test "generated module has correct domain" do
      domain = Extension.get_persisted(TestDomain.SimpleTemplate, :domain)
      assert domain == TestDomain
    end

    test "generated module has call and stream actions" do
      actions = ResourceInfo.actions(TestDomain.SimpleTemplate)
      action_names = Enum.map(actions, & &1.name)

      assert :call in action_names
      assert :stream in action_names
    end

    test "sets client from domain registration" do
      {client, _opts} = Extension.get_opt(TestDomain.SimpleTemplate, [:agent], :client)
      assert client == "anthropic:claude-3-5-haiku"
    end

    test "each agent gets its own client configuration" do
      {client, _opts} = Extension.get_opt(TestDomain.Rewriter, [:agent], :client)
      assert client == "openai:gpt-4o"
    end

    test "preserves client options when no override" do
      {_client, opts} = Extension.get_opt(TestDomain.SimpleTemplate, [:agent], :client)
      assert opts == []
    end

    test "domain has auto-generated interfaces for agents" do
      assert function_exported?(TestDomain, :call_simple_template, 1)
      assert function_exported?(TestDomain, :call_simple_template!, 1)
      assert function_exported?(TestDomain, :stream_simple_template, 1)
      assert function_exported?(TestDomain, :stream_simple_template!, 1)
    end
  end

  describe "provider override" do
    defmodule TemplateForProviderTest do
      use AshAgent.Template

      agent do
        input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
        output_schema(Zoi.object(%{result: Zoi.string()}, coerce: true))
        instruction(~p"Query: {{ query }}")
      end
    end

    defmodule DomainWithProviderOverride do
      use Ash.Domain,
        extensions: [AshAgent.Domain],
        validate_config_inclusion?: false

      agents do
        agent(AshAgent.Domain.Transformers.GenerateAgentsTest.TemplateForProviderTest,
          client: "anthropic:claude-3-5-haiku",
          provider: :mock
        )
      end
    end

    test "overrides provider when specified in domain" do
      provider =
        Extension.get_opt(DomainWithProviderOverride.TemplateForProviderTest, [:agent], :provider)

      assert provider == :mock
    end
  end

  describe "generated agents are identical to hand-written" do
    defmodule HandWrittenAgent do
      use Ash.Resource,
        domain: AshAgent.Domain.Transformers.GenerateAgentsTest.ComparisonDomain,
        extensions: [AshAgent.Resource]

      import AshAgent.Sigils

      resource do
        require_primary_key?(false)
      end

      agent do
        client "anthropic:claude-3-5-haiku"
        input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
        output_schema(Zoi.object(%{result: Zoi.string()}, coerce: true))
        instruction(~p"Echo: {{ message }}")
      end
    end

    defmodule ComparisonDomain do
      use Ash.Domain,
        extensions: [AshAgent.Domain],
        validate_config_inclusion?: false

      resources do
        resource AshAgent.Domain.Transformers.GenerateAgentsTest.HandWrittenAgent
      end

      agents do
        agent(AshAgent.Domain.Transformers.GenerateAgentsTest.SimpleTemplate,
          client: "anthropic:claude-3-5-haiku",
          as: :generated_agent
        )
      end
    end

    test "generated agent has same action structure as hand-written" do
      hand_written_actions = ResourceInfo.actions(HandWrittenAgent)
      generated_actions = ResourceInfo.actions(ComparisonDomain.GeneratedAgent)

      hand_written_names = Enum.map(hand_written_actions, & &1.name) |> Enum.sort()
      generated_names = Enum.map(generated_actions, & &1.name) |> Enum.sort()

      assert hand_written_names == generated_names
    end

    test "domain has auto-generated interfaces for both agents" do
      assert function_exported?(ComparisonDomain, :call_hand_written_agent, 1)
      assert function_exported?(ComparisonDomain, :call_generated_agent, 1)
      assert function_exported?(ComparisonDomain, :stream_hand_written_agent, 1)
      assert function_exported?(ComparisonDomain, :stream_generated_agent, 1)
    end
  end
end
