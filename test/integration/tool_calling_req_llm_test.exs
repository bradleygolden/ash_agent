defmodule AshAgent.Integration.ToolCallingReqLLMTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias AshAgent.TestDomain

  defmodule ReqLLMToolAgent do
    use Ash.Resource,
      domain: TestDomain,
      extensions: [AshAgent.Resource]

    import AshAgent.Sigils

    defmodule Reply do
      use Ash.TypedStruct

      typed_struct do
        field :content, :string, allow_nil?: false
        field :result, :integer
      end
    end

    agent do
      provider :req_llm
      client("openai:qwen3:1.7b",
        base_url: "http://localhost:11434/v1",
        api_key: "ollama",
        temperature: 0.0
      )

      output Reply

      input do
        argument :message, :string, allow_nil?: false
      end

      prompt ~p"""
      You are a helpful assistant with access to tools.
      When asked to perform calculations, use the add_numbers tool.
      Reply with JSON matching ctx.output_format exactly.
      {{ output_format }}
      """

      tools do
        max_iterations 3
        timeout 30_000
        on_error :continue

        tool :add_numbers do
          description "Add two numbers together"
          function {__MODULE__, :add, []}
          parameters [
            a: [type: :integer, required: true, description: "First number"],
            b: [type: :integer, required: true, description: "Second number"]
          ]
        end
      end
    end

    code_interface do
      define :call, args: [:message]
    end

    def add(%{a: a, b: b}, _context) do
      {:ok, %{result: a + b}}
    end
  end

  setup_all do
    ReqLLM.put_key(:openai_api_key, "ollama")
    :ok
  end

  setup do
    original_opts = Application.get_env(:ash_agent, :req_llm_options, [])
    Application.put_env(:ash_agent, :req_llm_options, [])

    on_exit(fn ->
      Application.put_env(:ash_agent, :req_llm_options, original_opts)
    end)

    :ok
  end

  describe "tool calling with req_llm provider" do
    @tag :integration
    test "executes tools in multi-turn conversation" do
      assert {:ok, %ReqLLMToolAgent.Reply{} = reply} =
               ReqLLMToolAgent.call(%{message: "What is 10 + 5? Use the tool to calculate."})

      assert is_binary(reply.content)
      assert reply.result == 15
    end
  end
end

