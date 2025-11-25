defmodule AshAgent.Providers.MockTest do
  use ExUnit.Case, async: true

  alias AshAgent.Providers.Mock

  describe "call/7" do
    test "returns default response when no mock_response provided" do
      {:ok, response} = Mock.call(nil, "prompt", [], [], %{}, nil, nil)

      assert response == %{"message" => "This is a mock response"}
    end

    test "returns custom mock_response from opts" do
      custom_response = %{"status" => "success", "data" => %{"id" => 123}}

      {:ok, response} =
        Mock.call(nil, "prompt", [], [mock_response: custom_response], %{}, nil, nil)

      assert response == custom_response
    end

    test "applies mock_delay_ms when provided" do
      start_time = System.monotonic_time(:millisecond)

      {:ok, _response} = Mock.call(nil, "prompt", [], [mock_delay_ms: 50], %{}, nil, nil)

      elapsed = System.monotonic_time(:millisecond) - start_time
      assert elapsed >= 50
    end

    test "ignores client parameter" do
      {:ok, response1} = Mock.call(:client1, "prompt", [], [], %{}, nil, nil)
      {:ok, response2} = Mock.call(:client2, "prompt", [], [], %{}, nil, nil)

      assert response1 == response2
    end

    test "ignores prompt parameter" do
      {:ok, response1} = Mock.call(nil, "Hello", [], [], %{}, nil, nil)
      {:ok, response2} = Mock.call(nil, "Goodbye", [], [], %{}, nil, nil)

      assert response1 == response2
    end

    test "ignores schema parameter" do
      {:ok, response1} = Mock.call(nil, "prompt", [name: :string], [], %{}, nil, nil)
      {:ok, response2} = Mock.call(nil, "prompt", [age: :integer], [], %{}, nil, nil)

      assert response1 == response2
    end

    test "ignores context parameter" do
      {:ok, response1} = Mock.call(nil, "prompt", [], [], %{agent: MyAgent}, nil, nil)
      {:ok, response2} = Mock.call(nil, "prompt", [], [], %{}, nil, nil)

      assert response1 == response2
    end

    test "ignores tools parameter" do
      {:ok, response1} = Mock.call(nil, "prompt", [], [], %{}, [%{name: "search"}], nil)
      {:ok, response2} = Mock.call(nil, "prompt", [], [], %{}, nil, nil)

      assert response1 == response2
    end

    test "ignores messages parameter" do
      {:ok, response1} =
        Mock.call(nil, "prompt", [], [], %{}, nil, [%{role: "user", content: "Hi"}])

      {:ok, response2} = Mock.call(nil, "prompt", [], [], %{}, nil, nil)

      assert response1 == response2
    end

    test "always returns :ok tuple" do
      result = Mock.call(nil, "prompt", [], [], %{}, nil, nil)

      assert {:ok, _response} = result
    end
  end

  describe "stream/7" do
    test "returns default chunks when no mock_chunks provided" do
      {:ok, stream} = Mock.stream(nil, "prompt", [], [], %{}, nil, nil)

      chunks = Enum.to_list(stream)

      assert chunks == [
               %{"delta" => "Mock "},
               %{"delta" => "streaming "},
               %{"delta" => "response"}
             ]
    end

    test "returns custom mock_chunks from opts" do
      custom_chunks = [
        %{"delta" => "Hello "},
        %{"delta" => "world!"}
      ]

      {:ok, stream} = Mock.stream(nil, "prompt", [], [mock_chunks: custom_chunks], %{}, nil, nil)

      chunks = Enum.to_list(stream)

      assert chunks == custom_chunks
    end

    test "applies mock_chunk_delay_ms between chunks" do
      chunks = [%{"delta" => "a"}, %{"delta" => "b"}, %{"delta" => "c"}]

      {:ok, stream} =
        Mock.stream(
          nil,
          "prompt",
          [],
          [mock_chunks: chunks, mock_chunk_delay_ms: 20],
          %{},
          nil,
          nil
        )

      start_time = System.monotonic_time(:millisecond)
      _result = Enum.to_list(stream)
      elapsed = System.monotonic_time(:millisecond) - start_time

      # 3 chunks * 20ms delay = 60ms minimum
      assert elapsed >= 60
    end

    test "stream is enumerable" do
      {:ok, stream} = Mock.stream(nil, "prompt", [], [], %{}, nil, nil)

      assert Enumerable.impl_for(stream) != nil
    end

    test "stream can be partially consumed" do
      {:ok, stream} = Mock.stream(nil, "prompt", [], [], %{}, nil, nil)

      first_chunk = Enum.take(stream, 1)

      assert first_chunk == [%{"delta" => "Mock "}]
    end

    test "ignores client parameter" do
      {:ok, stream1} = Mock.stream(:client1, "prompt", [], [], %{}, nil, nil)
      {:ok, stream2} = Mock.stream(:client2, "prompt", [], [], %{}, nil, nil)

      assert Enum.to_list(stream1) == Enum.to_list(stream2)
    end

    test "ignores prompt parameter" do
      {:ok, stream1} = Mock.stream(nil, "Hello", [], [], %{}, nil, nil)
      {:ok, stream2} = Mock.stream(nil, "Goodbye", [], [], %{}, nil, nil)

      assert Enum.to_list(stream1) == Enum.to_list(stream2)
    end

    test "always returns :ok tuple with stream" do
      result = Mock.stream(nil, "prompt", [], [], %{}, nil, nil)

      assert {:ok, stream} = result
      assert is_function(stream) or is_struct(stream)
    end
  end

  describe "introspect/0" do
    test "returns provider metadata map" do
      metadata = Mock.introspect()

      assert is_map(metadata)
    end

    test "identifies provider as :mock" do
      metadata = Mock.introspect()

      assert metadata.provider == :mock
    end

    test "lists supported features" do
      metadata = Mock.introspect()

      assert is_list(metadata.features)
      assert :sync_call in metadata.features
      assert :streaming in metadata.features
      assert :configurable_responses in metadata.features
      assert :tool_calling in metadata.features
    end

    test "lists available models" do
      metadata = Mock.introspect()

      assert is_list(metadata.models)
      assert "mock:test" in metadata.models
    end

    test "specifies unlimited max_tokens" do
      metadata = Mock.introspect()

      assert metadata.constraints.max_tokens == :unlimited
    end
  end

  describe "Provider behaviour compliance" do
    test "implements call/7 callback" do
      assert function_exported?(Mock, :call, 7)
    end

    test "implements stream/7 callback" do
      assert function_exported?(Mock, :stream, 7)
    end

    test "implements introspect/0 optional callback" do
      assert function_exported?(Mock, :introspect, 0)
    end
  end
end
