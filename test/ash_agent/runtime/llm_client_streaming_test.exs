defmodule AshAgent.Runtime.LLMClientStreamingTest do
  @moduledoc """
  Unit tests for streaming functionality in AshAgent.Runtime.LLMClient.

  These tests focus on:
  - stream_object/7 behavior
  - stream_to_structs/2 transformation
  - Error handling during streaming
  - Edge cases for stream processing
  """
  use ExUnit.Case, async: true

  alias AshAgent.Runtime.LLMClient
  alias AshAgent.Error

  defmodule StreamableOutput do
    @moduledoc false
    use Ash.TypedStruct

    typed_struct do
      field :content, :string, allow_nil?: false
      field :metadata, :map
    end
  end

  defmodule PartialOutput do
    @moduledoc false
    use Ash.TypedStruct

    typed_struct do
      field :text, :string
      field :complete, :boolean
    end
  end

  describe "stream_to_structs/2 with enumerable streams" do
    test "converts stream of maps to stream of structs" do
      input_stream =
        Stream.map(
          [
            %{"content" => "Hello", "metadata" => %{"key" => "value"}},
            %{"content" => "World", "metadata" => nil}
          ],
          & &1
        )

      result_stream = LLMClient.stream_to_structs(input_stream, StreamableOutput)
      results = Enum.to_list(result_stream)

      assert length(results) == 2

      assert %StreamableOutput{content: "Hello", metadata: %{"key" => "value"}} =
               Enum.at(results, 0)

      assert %StreamableOutput{content: "World", metadata: nil} = Enum.at(results, 1)
    end

    test "handles stream with atom keys" do
      input_stream = Stream.map([%{content: "test", metadata: nil}], & &1)

      result_stream = LLMClient.stream_to_structs(input_stream, StreamableOutput)
      results = Enum.to_list(result_stream)

      assert length(results) == 1
      assert %StreamableOutput{content: "test"} = hd(results)
    end

    test "handles empty stream" do
      input_stream = Stream.map([], & &1)

      result_stream = LLMClient.stream_to_structs(input_stream, StreamableOutput)
      results = Enum.to_list(result_stream)

      assert results == []
    end

    test "handles single element stream" do
      input_stream = Stream.map([%{"content" => "only"}], & &1)

      result_stream = LLMClient.stream_to_structs(input_stream, StreamableOutput)
      results = Enum.to_list(result_stream)

      assert length(results) == 1
    end

    test "preserves stream laziness" do
      call_count = :counters.new(1, [:atomics])

      input_stream =
        Stream.map(1..10, fn i ->
          :counters.add(call_count, 1, 1)
          %{"content" => "item_#{i}"}
        end)

      result_stream = LLMClient.stream_to_structs(input_stream, StreamableOutput)

      # No elements should be processed yet
      assert :counters.get(call_count, 1) == 0

      # Take only 2 elements
      _results = Enum.take(result_stream, 2)

      # Only 2 elements should have been processed
      assert :counters.get(call_count, 1) == 2
    end

    test "handles chunks that fail parsing gracefully" do
      unique_key = "nonexistent_key_#{System.unique_integer([:positive])}"

      input_stream =
        Stream.map(
          [
            %{"content" => "valid"},
            %{unique_key => "invalid"}
          ],
          & &1
        )

      result_stream = LLMClient.stream_to_structs(input_stream, StreamableOutput)
      results = Enum.to_list(result_stream)

      assert length(results) == 2
      assert %StreamableOutput{content: "valid"} = Enum.at(results, 0)
      assert %{^unique_key => "invalid"} = Enum.at(results, 1)
    end

    test "creates struct with extra atom keys when all keys exist as atoms" do
      input_stream =
        Stream.map(
          [
            %{content: "valid", metadata: nil},
            %{content: "with_extra", metadata: nil, some_extra_key: "ignored"}
          ],
          & &1
        )

      result_stream = LLMClient.stream_to_structs(input_stream, StreamableOutput)
      results = Enum.to_list(result_stream)

      assert length(results) == 2
      assert %StreamableOutput{content: "valid", metadata: nil} = Enum.at(results, 0)
      assert %StreamableOutput{content: "with_extra", metadata: nil} = Enum.at(results, 1)
    end
  end

  describe "stream_to_structs/2 with function streams" do
    test "handles function-based stream (arity 2)" do
      # Create a function that matches enumerable protocol
      stream_fn = fn acc, fun ->
        fun.({:cont, %{"content" => "from_fn"}}, acc)
      end

      result = LLMClient.stream_to_structs(stream_fn, StreamableOutput)

      # Should return a stream
      assert is_struct(result, Stream) or is_function(result, 2)
    end
  end

  describe "stream_to_structs/2 with struct chunks" do
    test "passes through chunks that are already the correct struct type" do
      existing_struct = %StreamableOutput{content: "already", metadata: nil}
      input_stream = Stream.map([existing_struct], & &1)

      result_stream = LLMClient.stream_to_structs(input_stream, StreamableOutput)
      results = Enum.to_list(result_stream)

      assert length(results) == 1
      assert ^existing_struct = hd(results)
    end

    test "converts different struct types to output type" do
      other_struct = %{__struct__: OtherStruct, content: "convert_me", metadata: nil}
      input_stream = Stream.map([other_struct], & &1)

      result_stream = LLMClient.stream_to_structs(input_stream, StreamableOutput)
      results = Enum.to_list(result_stream)

      assert length(results) == 1
      assert %StreamableOutput{content: "convert_me"} = hd(results)
    end
  end

  describe "stream_to_structs/2 with partial/progressive chunks" do
    test "handles progressive building of response" do
      # Simulate progressive chunks like BAML sends
      input_stream =
        Stream.map(
          [
            %{"text" => nil, "complete" => false},
            %{"text" => "partial", "complete" => false},
            %{"text" => "final result", "complete" => true}
          ],
          & &1
        )

      result_stream = LLMClient.stream_to_structs(input_stream, PartialOutput)
      results = Enum.to_list(result_stream)

      assert length(results) == 3
      assert %PartialOutput{text: nil, complete: false} = Enum.at(results, 0)
      assert %PartialOutput{text: "partial", complete: false} = Enum.at(results, 1)
      assert %PartialOutput{text: "final result", complete: true} = Enum.at(results, 2)
    end
  end

  describe "stream_object/7" do
    test "returns error when provider cannot be resolved" do
      result =
        LLMClient.stream_object(
          NonExistentResource,
          "client",
          "prompt",
          [],
          [],
          %{},
          provider_override: :unknown_provider
        )

      assert {:error, %Error{}} = result
    end

    test "returns error when provider stream fails" do
      defmodule FailingStreamProvider do
        @behaviour AshAgent.Provider

        def call(_, _, _, _, _, _, _), do: {:ok, %{}}

        def stream(_client, _prompt, _schema, _opts, _context, _tools, _messages) do
          {:error, "Stream failed"}
        end

        def introspect, do: %{provider: :failing_stream, features: [:streaming]}
      end

      # Need to use an agent resource to test this
      defmodule TestStreamResource do
        use Ash.Resource,
          domain: AshAgent.Runtime.LLMClientStreamingTest.TestDomain,
          extensions: [AshAgent.Resource]

        resource do
          require_primary_key? false
        end

        agent do
          provider FailingStreamProvider
          client :test
          output StreamableOutput
          prompt "test"
        end
      end

      defmodule TestDomain do
        use Ash.Domain, validate_config_inclusion?: false

        resources do
          allow_unregistered? true
          resource TestStreamResource
        end
      end

      result =
        LLMClient.stream_object(
          TestStreamResource,
          :test,
          "prompt",
          [],
          [],
          %{},
          provider_override: FailingStreamProvider
        )

      assert {:error, %Error{type: :llm_error}} = result
    end
  end

  describe "stream_to_structs/2 composition" do
    test "can be composed with Stream.filter" do
      input_stream =
        Stream.map(
          [
            %{"content" => "keep", "metadata" => nil},
            %{"content" => "skip", "metadata" => nil},
            %{"content" => "keep_too", "metadata" => nil}
          ],
          & &1
        )

      result_stream =
        input_stream
        |> LLMClient.stream_to_structs(StreamableOutput)
        |> Stream.filter(fn struct -> struct.content != "skip" end)

      results = Enum.to_list(result_stream)

      assert length(results) == 2
      assert Enum.all?(results, fn r -> r.content != "skip" end)
    end

    test "can be composed with Stream.map" do
      input_stream = Stream.map([%{"content" => "hello", "metadata" => nil}], & &1)

      result_stream =
        input_stream
        |> LLMClient.stream_to_structs(StreamableOutput)
        |> Stream.map(fn struct -> String.upcase(struct.content) end)

      results = Enum.to_list(result_stream)

      assert results == ["HELLO"]
    end

    test "can be composed with Stream.take" do
      input_stream =
        Stream.map(
          [
            %{"content" => "1"},
            %{"content" => "2"},
            %{"content" => "3"},
            %{"content" => "4"}
          ],
          & &1
        )

      result_stream =
        input_stream
        |> LLMClient.stream_to_structs(StreamableOutput)
        |> Stream.take(2)

      results = Enum.to_list(result_stream)

      assert length(results) == 2
    end

    test "can be composed with Enum.reduce" do
      input_stream =
        Stream.map(
          [
            %{"content" => "a"},
            %{"content" => "b"},
            %{"content" => "c"}
          ],
          & &1
        )

      result =
        input_stream
        |> LLMClient.stream_to_structs(StreamableOutput)
        |> Enum.reduce("", fn struct, acc -> acc <> struct.content end)

      assert result == "abc"
    end
  end

  describe "stream_to_structs/2 edge cases" do
    test "handles very large stream" do
      large_count = 1000

      input_stream =
        Stream.map(1..large_count, fn i ->
          %{"content" => "item_#{i}"}
        end)

      result_stream = LLMClient.stream_to_structs(input_stream, StreamableOutput)
      results = Enum.to_list(result_stream)

      assert length(results) == large_count
    end

    test "handles stream with mixed valid and invalid data" do
      input_stream =
        Stream.map(
          [
            %{"content" => "valid1"},
            nil,
            %{"content" => "valid2"},
            "string_chunk",
            %{"content" => "valid3"}
          ],
          & &1
        )

      result_stream = LLMClient.stream_to_structs(input_stream, StreamableOutput)

      # This should not raise, even with unusual chunk types
      results = Enum.to_list(result_stream)

      assert length(results) == 5
    end

    test "handles stream with only nil values" do
      input_stream = Stream.map([nil, nil, nil], & &1)

      result_stream = LLMClient.stream_to_structs(input_stream, StreamableOutput)
      results = Enum.to_list(result_stream)

      assert length(results) == 3
    end

    test "handles stream with empty maps" do
      input_stream = Stream.map([%{}, %{}, %{}], & &1)

      result_stream = LLMClient.stream_to_structs(input_stream, StreamableOutput)
      results = Enum.to_list(result_stream)

      assert length(results) == 3
      assert Enum.all?(results, &match?(%StreamableOutput{content: nil, metadata: nil}, &1))
    end

    test "handles stream with nested map content" do
      input_stream =
        Stream.map(
          [
            %{"content" => "test", "metadata" => %{"nested" => %{"deep" => "value"}}}
          ],
          & &1
        )

      result_stream = LLMClient.stream_to_structs(input_stream, StreamableOutput)
      results = Enum.to_list(result_stream)

      assert length(results) == 1

      assert %StreamableOutput{content: "test", metadata: %{"nested" => %{"deep" => "value"}}} =
               hd(results)
    end

    test "handles stream with unicode content" do
      input_stream =
        Stream.map(
          [
            %{"content" => "Hello 世界 🌍"},
            %{"content" => "Élève résumé"},
            %{"content" => "日本語テスト"}
          ],
          & &1
        )

      result_stream = LLMClient.stream_to_structs(input_stream, StreamableOutput)
      results = Enum.to_list(result_stream)

      assert length(results) == 3
      assert Enum.at(results, 0).content == "Hello 世界 🌍"
      assert Enum.at(results, 1).content == "Élève résumé"
      assert Enum.at(results, 2).content == "日本語テスト"
    end

    test "handles stream with very long content strings" do
      long_content = String.duplicate("a", 100_000)
      input_stream = Stream.map([%{"content" => long_content}], & &1)

      result_stream = LLMClient.stream_to_structs(input_stream, StreamableOutput)
      results = Enum.to_list(result_stream)

      assert length(results) == 1
      assert String.length(hd(results).content) == 100_000
    end

    test "handles rapid sequential consumption" do
      input_stream =
        Stream.map(1..100, fn i ->
          %{"content" => "item_#{i}"}
        end)

      result_stream = LLMClient.stream_to_structs(input_stream, StreamableOutput)

      first_50 = Enum.take(result_stream, 50)
      assert length(first_50) == 50
    end
  end

  describe "stream_to_structs/2 error resilience" do
    test "continues after encountering nil chunk" do
      input_stream =
        Stream.map(
          [
            %{"content" => "before"},
            nil,
            %{"content" => "after"}
          ],
          & &1
        )

      result_stream = LLMClient.stream_to_structs(input_stream, StreamableOutput)
      results = Enum.to_list(result_stream)

      valid_results =
        Enum.filter(results, &match?(%StreamableOutput{content: c} when c != nil, &1))

      assert length(valid_results) == 2
    end

    test "handles struct with missing required field gracefully" do
      input_stream = Stream.map([%{"metadata" => %{"key" => "value"}}], & &1)

      result_stream = LLMClient.stream_to_structs(input_stream, StreamableOutput)
      results = Enum.to_list(result_stream)

      assert length(results) == 1
      assert %StreamableOutput{content: nil, metadata: %{"key" => "value"}} = hd(results)
    end

    test "handles mixed string and atom keys in same stream" do
      input_stream =
        Stream.map(
          [
            %{"content" => "string_key"},
            %{content: "atom_key"},
            %{"content" => "back_to_string"}
          ],
          & &1
        )

      result_stream = LLMClient.stream_to_structs(input_stream, StreamableOutput)
      results = Enum.to_list(result_stream)

      assert length(results) == 3
      assert Enum.at(results, 0).content == "string_key"
      assert Enum.at(results, 1).content == "atom_key"
      assert Enum.at(results, 2).content == "back_to_string"
    end
  end

  describe "stream_to_structs/2 memory efficiency" do
    test "does not hold all elements in memory at once" do
      call_count = :counters.new(1, [:atomics])

      input_stream =
        Stream.map(1..1000, fn i ->
          :counters.add(call_count, 1, 1)
          %{"content" => "item_#{i}"}
        end)

      result_stream = LLMClient.stream_to_structs(input_stream, StreamableOutput)

      assert :counters.get(call_count, 1) == 0

      _first_10 = Enum.take(result_stream, 10)

      assert :counters.get(call_count, 1) == 10
    end

    test "supports infinite streams with take" do
      infinite_stream =
        Stream.iterate(0, &(&1 + 1))
        |> Stream.map(fn i -> %{"content" => "item_#{i}"} end)

      result_stream = LLMClient.stream_to_structs(infinite_stream, StreamableOutput)

      results = Enum.take(result_stream, 5)

      assert length(results) == 5
      assert Enum.at(results, 0).content == "item_0"
      assert Enum.at(results, 4).content == "item_4"
    end
  end
end
