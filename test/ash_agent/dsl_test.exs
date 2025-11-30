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
      assert :input_schema in schema_keys
      assert :output_schema in schema_keys
      assert :instruction in schema_keys
      assert :hooks in schema_keys
      assert :token_budget in schema_keys
      assert :budget_strategy in schema_keys
    end

    test "input_schema is required" do
      agent_section = DSL.agent()
      input_schema_opt = Keyword.get(agent_section.schema, :input_schema)

      assert input_schema_opt[:required] == true
    end

    test "output_schema is required" do
      agent_section = DSL.agent()
      output_schema_opt = Keyword.get(agent_section.schema, :output_schema)

      assert output_schema_opt[:required] == true
    end
  end
end
