defmodule AshAgent.Actions.StreamTest do
  @moduledoc """
  Unit tests for AshAgent.Actions.Stream.

  Tests the Ash action implementation for streaming responses.
  """
  use ExUnit.Case, async: true

  alias AshAgent.Actions.Stream, as: StreamAction

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
      input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
      output_schema(Zoi.object(%{content: Zoi.string()}, coerce: true))
      instruction("Test stream prompt")
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
      context = AshAgent.Context.new([AshAgent.Message.user(%{message: "test"})])
      input = %{resource: TestStreamAgent, arguments: %{context: context}}

      assert {:ok, stream} = StreamAction.run(input, [], %{})
      assert is_function(stream) or is_struct(stream, Elixir.Stream)
    end

    test "stream yields tagged chunks when consumed" do
      context = AshAgent.Context.new([AshAgent.Message.user(%{message: "test"})])
      input = %{resource: TestStreamAgent, arguments: %{context: context}}

      {:ok, stream} = StreamAction.run(input, [], %{})
      results = Enum.to_list(stream)

      content_chunks = Enum.filter(results, &match?({:content, _}, &1))
      done_chunks = Enum.filter(results, &match?({:done, _}, &1))

      assert length(content_chunks) == 2
      assert {:content, %{content: "chunk1"}} = Enum.at(content_chunks, 0)
      assert {:content, %{content: "chunk2"}} = Enum.at(content_chunks, 1)

      assert length(done_chunks) == 1
      assert {:done, %AshAgent.Result{output: %{content: _}}} = Enum.at(done_chunks, 0)
    end

    test "passes arguments through to runtime" do
      context = AshAgent.Context.new([AshAgent.Message.user(%{message: "test"})])
      input = %{resource: TestStreamAgent, arguments: %{context: context, custom_arg: "value"}}

      assert {:ok, _stream} = StreamAction.run(input, [], %{})
    end

    test "handles empty context messages" do
      context = AshAgent.Context.new([])
      input = %{resource: TestStreamAgent, arguments: %{context: context}}

      assert {:ok, stream} = StreamAction.run(input, [], %{})
      assert Enum.to_list(stream) != []
    end

    test "returns error for invalid resource" do
      context = AshAgent.Context.new([])
      input = %{resource: NonExistentModule, arguments: %{context: context}}

      assert {:error, _} = StreamAction.run(input, [], %{})
    end
  end

  describe "run/3 stream behavior" do
    test "stream supports early termination" do
      context = AshAgent.Context.new([AshAgent.Message.user(%{message: "test"})])
      input = %{resource: TestStreamAgent, arguments: %{context: context}}

      {:ok, stream} = StreamAction.run(input, [], %{})
      results = Enum.take(stream, 1)

      assert length(results) == 1
    end
  end
end
