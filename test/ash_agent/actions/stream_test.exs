defmodule AshAgent.Actions.StreamTest do
  @moduledoc """
  Unit tests for AshAgent.Actions.Stream.

  Tests the Ash action implementation for streaming responses.
  """
  use ExUnit.Case, async: true

  alias AshAgent.Actions.Stream, as: StreamAction

  defmodule StreamOutput do
    @moduledoc false
    use Ash.TypedStruct

    typed_struct do
      field :content, :string, allow_nil?: false
    end
  end

  defmodule StreamMockProvider do
    @behaviour AshAgent.Provider

    def call(_client, _prompt, _schema, _opts, _context, _tools, _messages) do
      {:ok, %{content: "call_response"}}
    end

    def stream(_client, _prompt, _schema, opts, _context, _tools, _messages) do
      chunks = Keyword.get(opts, :mock_chunks, [%{content: "chunk1"}, %{content: "chunk2"}])
      {:ok, Stream.map(chunks, & &1)}
    end

    def introspect do
      %{provider: :stream_mock, features: [:sync_call, :streaming]}
    end
  end

  defmodule TestStreamAgent do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.Actions.StreamTest.TestDomain,
      extensions: [AshAgent.Resource]

    resource do
      require_primary_key? false
    end

    agent do
      provider StreamMockProvider
      client :mock
      output StreamOutput
      prompt "Test stream prompt"
    end
  end

  defmodule TestDomain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      allow_unregistered? true
      resource TestStreamAgent
    end
  end

  describe "run/3" do
    test "returns ok tuple with stream for valid input" do
      input = %{resource: TestStreamAgent, arguments: %{}}

      assert {:ok, stream} = StreamAction.run(input, [], %{})
      assert is_function(stream) or is_struct(stream, Elixir.Stream)
    end

    test "stream yields chunks when consumed" do
      input = %{resource: TestStreamAgent, arguments: %{}}

      {:ok, stream} = StreamAction.run(input, [], %{})
      results = Enum.to_list(stream)

      assert length(results) == 2
      assert %StreamOutput{content: "chunk1"} = Enum.at(results, 0)
      assert %StreamOutput{content: "chunk2"} = Enum.at(results, 1)
    end

    test "passes arguments through to runtime" do
      input = %{resource: TestStreamAgent, arguments: %{custom_arg: "value"}}

      assert {:ok, _stream} = StreamAction.run(input, [], %{})
    end

    test "handles empty arguments" do
      input = %{resource: TestStreamAgent, arguments: %{}}

      assert {:ok, stream} = StreamAction.run(input, [], %{})
      assert Enum.to_list(stream) != []
    end

    test "returns error for invalid resource" do
      input = %{resource: NonExistentModule, arguments: %{}}

      assert {:error, _} = StreamAction.run(input, [], %{})
    end
  end

  describe "run/3 stream behavior" do
    test "stream supports early termination" do
      input = %{resource: TestStreamAgent, arguments: %{}}

      {:ok, stream} = StreamAction.run(input, [], %{})
      results = Enum.take(stream, 1)

      assert length(results) == 1
    end
  end
end
