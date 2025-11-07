defmodule AshAgent.Integration.ToolCallingTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias AshAgent.TestDomain

  defmodule MockToolAgent do
    use Ash.Resource,
      domain: TestDomain,
      extensions: [AshAgent.Resource]

    import AshAgent.Sigils

    defmodule Reply do
      use Ash.TypedStruct

      typed_struct do
        field :content, :string, allow_nil?: false
      end
    end

    agent do
      provider :mock
      client "mock:test"

      output Reply

      input do
        argument :message, :string, allow_nil?: false
      end

      prompt ~p"""
      You are a helpful assistant.
      {{ output_format }}
      """

      tools do
        max_iterations 3
        timeout 10_000
        on_error :continue

        tool :add_numbers do
          description "Add two numbers together"
          function {__MODULE__, :add, []}
          parameters [
            a: [type: :integer, required: true, description: "First number"],
            b: [type: :integer, required: true, description: "Second number"]
          ]
        end

        tool :get_message do
          description "Get the original message"
          function {__MODULE__, :get_message, []}
          parameters []
        end
      end
    end

    code_interface do
      define :call, args: [:message]
    end

    def add(%{a: a, b: b}, %{input: %{message: _message}}) do
      {:ok, %{result: a + b}}
    end

    def get_message(_args, %{input: %{message: message}}) do
      {:ok, %{message: message}}
    end
  end

  setup do
    original_opts = Application.get_env(:ash_agent, :req_llm_options, [])
    Application.put_env(:ash_agent, :req_llm_options, [])

    on_exit(fn ->
      Application.put_env(:ash_agent, :req_llm_options, original_opts)
    end)

    :ok
  end

  describe "tool calling with mock provider" do
    test "executes tools when LLM requests them" do
      Req.Test.stub(AshAgent.LLMStub, fn conn ->
        case Req.Request.get_header(conn, "content-type") do
          "application/json" ->
            body = Jason.decode!(conn.body)

            if Map.has_key?(body, "tools") do
              Req.Test.json(conn, %{
                "id" => "msg_1",
                "type" => "message",
                "role" => "assistant",
                "content" => [],
                "model" => "mock",
                "stop_reason" => "tool_use",
                "tool_calls" => [
                  %{
                    "id" => "toolu_1",
                    "type" => "function",
                    "function" => %{
                      "name" => "add_numbers",
                      "arguments" => Jason.encode!(%{a: 5, b: 3})
                    }
                  }
                ]
              })
            else
              Req.Test.json(conn, %{
                "id" => "msg_2",
                "type" => "message",
                "role" => "assistant",
                "content" => [
                  %{
                    "type" => "text",
                    "text" => "The result is 8"
                  }
                ],
                "model" => "mock",
                "stop_reason" => "end_turn"
              })
            end
        end
      end)

      Application.put_env(:ash_agent, :req_llm_options,
        req_http_options: [plug: {Req.Test, AshAgent.LLMStub}]
      )

      assert {:ok, %MockToolAgent.Reply{} = reply} =
               MockToolAgent.call(%{message: "What is 5 + 3?"})

      assert String.contains?(reply.content, "8")
    end
  end
end

