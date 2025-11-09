defmodule AshAgent.DSL.ToolsTest do
  use ExUnit.Case, async: true

  alias Spark.Dsl.Extension

  defmodule TestAgent do
    use Ash.Resource,
      domain: AshAgent.TestDomain,
      extensions: [AshAgent.Resource]

    import AshAgent.Sigils, only: [sigil_p: 2]

    resource do
      require_primary_key? false
    end

    defmodule Reply do
      use Ash.TypedStruct

      typed_struct do
        field(:content, :string, allow_nil?: false)
      end
    end

    agent do
      client("mock:test-model")

      input do
        argument(:message, :string, allow_nil?: false)
      end

      output(Reply)

      prompt(~p"""
      Test prompt
      """)
    end

    tools do
      max_iterations(5)
      timeout 60_000
      on_error(:continue)

      tool :test_function do
        description("A test function tool")
        function({__MODULE__, :test_func, []})

        parameters(arg1: [type: :string, required: true, description: "First argument"])
      end
    end

    def test_func(_args, _context), do: {:ok, %{result: "success"}}
  end

  describe "tools DSL" do
    test "allows defining tools section" do
      tools_config = Extension.get_opt(TestAgent, [:tools], :max_iterations)
      assert tools_config == 5
    end

    test "stores tool definitions" do
      tools = Extension.get_entities(TestAgent, [:tools])
      assert length(tools) == 1

      tool = List.first(tools)
      assert tool.name == :test_function
      assert tool.description == "A test function tool"
      assert tool.function == {AshAgent.DSL.ToolsTest.TestAgent, :test_func, []}
    end

    test "validates timeout configuration" do
      timeout = Extension.get_opt(TestAgent, [:tools], :timeout)
      assert timeout == 60_000
    end

    test "validates on_error configuration" do
      on_error = Extension.get_opt(TestAgent, [:tools], :on_error)
      assert on_error == :continue
    end
  end
end
