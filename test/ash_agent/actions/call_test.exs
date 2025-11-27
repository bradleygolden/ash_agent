defmodule AshAgent.Actions.CallTest do
  @moduledoc """
  Unit tests for AshAgent.Actions.Call.

  Tests the Ash action implementation for synchronous calls.
  """
  use ExUnit.Case, async: true

  alias AshAgent.Actions.Call

  defmodule CallOutput do
    @moduledoc false
    use Ash.TypedStruct

    typed_struct do
      field :message, :string, allow_nil?: false
    end
  end

  defmodule CallMockProvider do
    @behaviour AshAgent.Provider

    def call(_client, _prompt, _schema, opts, _context, _tools, _messages) do
      response = Keyword.get(opts, :mock_response, %{message: "default_response"})
      {:ok, response}
    end

    def stream(_client, _prompt, _schema, _opts, _context, _tools, _messages) do
      {:error, :not_supported}
    end

    def introspect do
      %{provider: :call_mock, features: [:sync_call]}
    end
  end

  defmodule TestCallAgent do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.Actions.CallTest.TestDomain,
      extensions: [AshAgent.Resource]

    resource do
      require_primary_key? false
    end

    agent do
      provider CallMockProvider
      client :mock
      output CallOutput
      prompt "Test call prompt"
    end
  end

  defmodule TestDomain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      allow_unregistered? true
      resource TestCallAgent
    end
  end

  describe "run/3" do
    test "returns ok tuple with result for valid input" do
      input = %{resource: TestCallAgent, arguments: %{}}

      assert {:ok, %AshAgent.Result{output: %CallOutput{}}} = Call.run(input, [], %{})
    end

    test "result contains expected content" do
      input = %{resource: TestCallAgent, arguments: %{}}

      {:ok, result} = Call.run(input, [], %{})

      assert result.output.message == "default_response"
    end

    test "passes arguments through to runtime" do
      input = %{resource: TestCallAgent, arguments: %{custom_arg: "value"}}

      assert {:ok, _result} = Call.run(input, [], %{})
    end

    test "handles empty arguments" do
      input = %{resource: TestCallAgent, arguments: %{}}

      assert {:ok, %AshAgent.Result{output: %CallOutput{}}} = Call.run(input, [], %{})
    end

    test "returns error for invalid resource" do
      input = %{resource: NonExistentModule, arguments: %{}}

      assert {:error, _} = Call.run(input, [], %{})
    end
  end
end
