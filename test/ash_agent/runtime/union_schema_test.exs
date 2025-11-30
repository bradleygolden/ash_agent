defmodule AshAgent.Runtime.UnionSchemaTest do
  @moduledoc """
  Tests for Zoi.union() output schemas supporting agentic loop patterns.
  """
  use ExUnit.Case, async: true

  alias AshAgent.Runtime

  defmodule UnionMockProvider do
    @behaviour AshAgent.Provider

    def call(_client, _prompt, _schema, opts, _context, _tools, _messages) do
      response = Keyword.get(opts, :mock_response, %{action: "response", content: "default"})
      {:ok, response}
    end

    def stream(_client, _prompt, _schema, _opts, _context, _tools, _messages) do
      {:error, :not_supported}
    end

    def introspect do
      %{provider: :union_mock, features: [:sync_call]}
    end
  end

  defmodule AgenticLoopAgent do
    use Ash.Resource,
      domain: AshAgent.Runtime.UnionSchemaTest.TestDomain,
      extensions: [AshAgent.Resource]

    resource do
      require_primary_key? false
    end

    agent do
      provider UnionMockProvider
      client :mock

      input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))

      output_schema(
        Zoi.union([
          # Tool call variant
          Zoi.object(
            %{
              action: Zoi.literal("tool_call"),
              tool_name: Zoi.string(),
              arguments: Zoi.map()
            },
            coerce: true
          ),

          # Final response variant
          Zoi.object(
            %{
              action: Zoi.literal("response"),
              content: Zoi.string()
            },
            coerce: true
          )
        ])
      )

      instruction("Test union schema")
    end
  end

  defmodule TestDomain do
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      allow_unregistered? true
      resource AgenticLoopAgent
    end
  end

  describe "union schema for agentic loops" do
    test "parses tool_call variant correctly" do
      {:ok, result} =
        Runtime.call(AgenticLoopAgent, %{},
          client_opts: [
            mock_response: %{
              "action" => "tool_call",
              "tool_name" => "search",
              "arguments" => %{"query" => "elixir"}
            }
          ]
        )

      assert %{action: "tool_call", tool_name: "search", arguments: args} = result.output
      assert args["query"] == "elixir"
    end

    test "parses response variant correctly" do
      {:ok, result} =
        Runtime.call(AgenticLoopAgent, %{},
          client_opts: [
            mock_response: %{
              "action" => "response",
              "content" => "Here is your answer"
            }
          ]
        )

      assert %{action: "response", content: "Here is your answer"} = result.output
    end

    test "can pattern match on discriminator for loop control" do
      # Simulate tool call
      {:ok, tool_result} =
        Runtime.call(AgenticLoopAgent, %{},
          client_opts: [
            mock_response: %{
              "action" => "tool_call",
              "tool_name" => "calculate",
              "arguments" => %{"expr" => "2+2"}
            }
          ]
        )

      # Pattern match determines next action
      next_action =
        case tool_result.output do
          %{action: "tool_call", tool_name: name} -> {:execute_tool, name}
          %{action: "response", content: content} -> {:done, content}
        end

      assert {:execute_tool, "calculate"} = next_action

      # Simulate final response
      {:ok, final_result} =
        Runtime.call(AgenticLoopAgent, %{},
          client_opts: [
            mock_response: %{
              "action" => "response",
              "content" => "The answer is 4"
            }
          ]
        )

      final_action =
        case final_result.output do
          %{action: "tool_call", tool_name: name} -> {:execute_tool, name}
          %{action: "response", content: content} -> {:done, content}
        end

      assert {:done, "The answer is 4"} = final_action
    end
  end
end
