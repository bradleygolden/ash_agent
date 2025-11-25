defmodule AshAgent.DSLTest do
  use ExUnit.Case, async: true

  alias AshAgent.DSL

  describe "validate_client_config/1" do
    test "accepts string client" do
      assert {:ok, {"anthropic:claude-3-5-sonnet", []}} =
               DSL.validate_client_config("anthropic:claude-3-5-sonnet")
    end

    test "accepts atom client" do
      assert {:ok, {:my_client, []}} = DSL.validate_client_config(:my_client)
    end

    test "accepts string client with keyword options" do
      assert {:ok, {"anthropic:claude-3-5-sonnet", [temperature: 0.7, max_tokens: 1000]}} =
               DSL.validate_client_config([
                 "anthropic:claude-3-5-sonnet",
                 temperature: 0.7,
                 max_tokens: 1000
               ])
    end

    test "accepts atom client with keyword options" do
      assert {:ok, {:my_client, [timeout: 5000]}} =
               DSL.validate_client_config([:my_client, timeout: 5000])
    end

    test "returns error for invalid client type" do
      assert {:error, message} = DSL.validate_client_config(123)
      assert message =~ "client must be a string or atom"
    end

    test "returns error for list with invalid first element" do
      assert {:error, message} = DSL.validate_client_config([123, temperature: 0.7])
      assert message =~ "client must be a string or atom"
    end

    test "returns error for map input" do
      assert {:error, message} = DSL.validate_client_config(%{client: "test"})
      assert message =~ "client must be a string or atom"
    end
  end

  describe "Argument struct" do
    test "has expected fields" do
      arg = %DSL.Argument{
        name: :message,
        type: :string,
        allow_nil?: false,
        default: nil,
        doc: "The user message"
      }

      assert arg.name == :message
      assert arg.type == :string
      assert arg.allow_nil? == false
      assert arg.default == nil
      assert arg.doc == "The user message"
    end

    test "default values when not specified" do
      arg = %DSL.Argument{name: :test, type: :string}

      assert arg.allow_nil? == nil
      assert arg.default == nil
      assert arg.doc == nil
    end
  end

  describe "agent/0" do
    test "returns agent section definition" do
      agent_section = DSL.agent()

      assert %Spark.Dsl.Section{} = agent_section
      assert agent_section.name == :agent
    end

    test "agent section has expected schema options" do
      agent_section = DSL.agent()
      schema_keys = Keyword.keys(agent_section.schema)

      assert :provider in schema_keys
      assert :client in schema_keys
      assert :output in schema_keys
      assert :prompt in schema_keys
      assert :hooks in schema_keys
      assert :token_budget in schema_keys
      assert :budget_strategy in schema_keys
    end

    test "agent section contains input subsection" do
      agent_section = DSL.agent()
      section_names = Enum.map(agent_section.sections, & &1.name)

      assert :input in section_names
    end
  end

  describe "input/0" do
    test "returns input section definition" do
      input_section = DSL.input()

      assert %Spark.Dsl.Section{} = input_section
      assert input_section.name == :input
    end

    test "input section has argument entity" do
      input_section = DSL.input()
      entity_names = Enum.map(input_section.entities, & &1.name)

      assert :argument in entity_names
    end
  end
end
