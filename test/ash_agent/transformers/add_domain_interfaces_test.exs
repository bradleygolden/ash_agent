defmodule AshAgent.Transformers.AddDomainInterfacesTest do
  use ExUnit.Case, async: true

  defmodule ChatAgent do
    use Ash.Resource,
      domain: AshAgent.Transformers.AddDomainInterfacesTest.TestDomain,
      extensions: [AshAgent.Resource]

    import AshAgent.Sigils

    resource do
      require_primary_key? false
    end

    agent do
      client "anthropic:claude-3-5-sonnet"
      input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
      output_schema(Zoi.object(%{response: Zoi.string()}, coerce: true))

      instruction(~p"""
      You are a chat assistant.
      User: {{ message }}
      """)
    end
  end

  defmodule SummaryAgent do
    use Ash.Resource,
      domain: AshAgent.Transformers.AddDomainInterfacesTest.TestDomain,
      extensions: [AshAgent.Resource]

    import AshAgent.Sigils

    resource do
      require_primary_key? false
    end

    agent do
      client "anthropic:claude-3-5-sonnet"
      input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
      output_schema(Zoi.object(%{response: Zoi.string()}, coerce: true))

      instruction(~p"""
      Summarize: {{ text }}
      """)
    end
  end

  defmodule NonAgentResource do
    use Ash.Resource,
      domain: AshAgent.Transformers.AddDomainInterfacesTest.TestDomain

    attributes do
      uuid_primary_key :id
    end
  end

  defmodule TestDomain do
    use Ash.Domain,
      extensions: [AshAgent.Domain],
      validate_config_inclusion?: false

    resources do
      resource AshAgent.Transformers.AddDomainInterfacesTest.ChatAgent
      resource AshAgent.Transformers.AddDomainInterfacesTest.SummaryAgent
      resource AshAgent.Transformers.AddDomainInterfacesTest.NonAgentResource
    end
  end

  defmodule AgentForDisabledDomain do
    use Ash.Resource,
      domain: AshAgent.Transformers.AddDomainInterfacesTest.DisabledDomain,
      extensions: [AshAgent.Resource]

    import AshAgent.Sigils

    resource do
      require_primary_key? false
    end

    agent do
      client "anthropic:claude-3-5-sonnet"
      input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
      output_schema(Zoi.object(%{response: Zoi.string()}, coerce: true))
      instruction(~p"Query: {{ query }}")
    end
  end

  defmodule DisabledDomain do
    use Ash.Domain,
      extensions: [AshAgent.Domain],
      validate_config_inclusion?: false

    agent do
      auto_define_interfaces?(false)
    end

    resources do
      resource AshAgent.Transformers.AddDomainInterfacesTest.AgentForDisabledDomain
    end
  end

  defmodule AgentWithManualDefine do
    use Ash.Resource,
      domain: AshAgent.Transformers.AddDomainInterfacesTest.ManualDefineDomain,
      extensions: [AshAgent.Resource]

    import AshAgent.Sigils

    resource do
      require_primary_key? false
    end

    agent do
      client "anthropic:claude-3-5-sonnet"
      input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
      output_schema(Zoi.object(%{response: Zoi.string()}, coerce: true))
      instruction(~p"Input: {{ input }}")
    end
  end

  defmodule ManualDefineDomain do
    use Ash.Domain,
      extensions: [AshAgent.Domain],
      validate_config_inclusion?: false

    resources do
      resource AshAgent.Transformers.AddDomainInterfacesTest.AgentWithManualDefine do
        define :call_agent_with_manual_define, action: :call, args: [:context]
      end
    end
  end

  describe "AddDomainInterfaces transformer" do
    test "auto-generates call_<name> and stream_<name> interfaces for agent resources" do
      references = Ash.Domain.Info.resource_references(TestDomain)
      chat_ref = Enum.find(references, &(&1.resource == ChatAgent))

      interface_names = Enum.map(chat_ref.definitions, & &1.name)

      assert :call_chat_agent in interface_names
      assert :stream_chat_agent in interface_names
    end

    test "call interface maps to :call action" do
      references = Ash.Domain.Info.resource_references(TestDomain)
      chat_ref = Enum.find(references, &(&1.resource == ChatAgent))

      call_interface = Enum.find(chat_ref.definitions, &(&1.name == :call_chat_agent))

      assert call_interface.action == :call
    end

    test "does not add interfaces for non-agent resources" do
      references = Ash.Domain.Info.resource_references(TestDomain)
      non_agent_ref = Enum.find(references, &(&1.resource == NonAgentResource))

      assert non_agent_ref.definitions == []
    end

    test "does not add interfaces when auto_define_interfaces? is false" do
      references = Ash.Domain.Info.resource_references(DisabledDomain)
      agent_ref = Enum.find(references, &(&1.resource == AgentForDisabledDomain))

      assert agent_ref.definitions == []
    end

    test "does not duplicate manually defined interfaces" do
      references = Ash.Domain.Info.resource_references(ManualDefineDomain)
      agent_ref = Enum.find(references, &(&1.resource == AgentWithManualDefine))

      call_interfaces =
        Enum.filter(agent_ref.definitions, &(&1.name == :call_agent_with_manual_define))

      assert length(call_interfaces) == 1

      stream_interfaces =
        Enum.filter(agent_ref.definitions, &(&1.name == :stream_agent_with_manual_define))

      assert length(stream_interfaces) == 1
    end

    test "generated functions are callable on the domain" do
      assert function_exported?(TestDomain, :call_chat_agent, 1)
      assert function_exported?(TestDomain, :call_chat_agent, 2)
      assert function_exported?(TestDomain, :stream_chat_agent, 1)
      assert function_exported?(TestDomain, :stream_chat_agent, 2)
    end
  end

  describe "AshAgent.Info.auto_define_interfaces?/1" do
    test "returns true by default" do
      assert AshAgent.Info.auto_define_interfaces?(TestDomain) == true
    end

    test "returns false when explicitly disabled" do
      assert AshAgent.Info.auto_define_interfaces?(DisabledDomain) == false
    end
  end
end
