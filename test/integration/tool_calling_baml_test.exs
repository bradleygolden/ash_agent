defmodule AshAgent.Integration.ToolCallingBamlTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  alias AshAgent.TestDomain

  defmodule BamlToolAgent do
    use Ash.Resource,
      domain: TestDomain,
      extensions: [AshAgent.Resource]

    defmodule Reply do
      use Ash.TypedStruct

      typed_struct do
        field :content, :string, allow_nil?: false
        field :confidence, :float
      end
    end

    agent do
      provider :baml
      client :ollama, function: :AgentEcho
      output Reply

      input do
        argument :message, :string, allow_nil?: false
      end

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

    def add(%{a: a, b: b}, _context) do
      {:ok, %{result: a + b}}
    end

    def get_message(_args, %{input: %{message: message}}) do
      {:ok, %{message: message}}
    end
  end

  describe "tool calling with baml provider" do
    @tag :integration
    # test "executes tools in multi-turn conversation" do
    #   assert {:ok, %BamlToolAgent.Reply{} = reply} =
    #            BamlToolAgent.call("What is 5 + 3? Use the add_numbers tool to calculate.")
    #
    #   assert is_binary(reply.content)
    #   assert String.length(reply.content) > 0
    #   assert is_float(reply.confidence)
    # end
  end
end

