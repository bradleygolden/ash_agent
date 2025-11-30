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

  alias AshAgent.Error
  alias AshAgent.Runtime.LLMClient

  @streamable_schema Zoi.object(
                       %{
                         content: Zoi.string(),
                         metadata: Zoi.map() |> Zoi.nullable() |> Zoi.optional()
                       },
                       coerce: true
                     )
  @partial_schema Zoi.object(
                    %{
                      text: Zoi.string() |> Zoi.nullable() |> Zoi.optional(),
                      complete: Zoi.boolean()
                    },
                    coerce: true
                  )

  describe "stream_to_structs/2 with enumerable streams" do
    test "converts stream of maps to validated maps" do
      input_stream =
        Stream.map(
          [
            %{"content" => "Hello", "metadata" => %{"key" => "value"}},
            %{"content" => "World", "metadata" => nil}
          ],
          & &1
        )

      result_stream = LLMClient.stream_to_structs(input_stream, @streamable_schema)
      results = Enum.to_list(result_stream)

      assert length(results) == 2

      assert %{content: "Hello", metadata: %{"key" => "value"}} = Enum.at(results, 0)
      assert %{content: "World", metadata: nil} = Enum.at(results, 1)
    end

    test "handles stream with atom keys" do
      input_stream = Stream.map([%{content: "test", metadata: nil}], & &1)

      result_stream = LLMClient.stream_to_structs(input_stream, @streamable_schema)
      results = Enum.to_list(result_stream)

      assert length(results) == 1
      assert %{content: "test"} = hd(results)
    end

    test "handles empty stream" do
      input_stream = Stream.map([], & &1)

      result_stream = LLMClient.stream_to_structs(input_stream, @streamable_schema)
      results = Enum.to_list(result_stream)

      assert results == []
    end

    test "handles single element stream" do
      input_stream = Stream.map([%{"content" => "only"}], & &1)

      result_stream = LLMClient.stream_to_structs(input_stream, @streamable_schema)
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

      result_stream = LLMClient.stream_to_structs(input_stream, @streamable_schema)

      assert :counters.get(call_count, 1) == 0

      _results = Enum.take(result_stream, 2)

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

      result_stream = LLMClient.stream_to_structs(input_stream, @streamable_schema)
      results = Enum.to_list(result_stream)

      assert length(results) == 2
      assert %{content: "valid"} = Enum.at(results, 0)
      assert %{^unique_key => "invalid"} = Enum.at(results, 1)
    end

    test "handles extra atom keys in input" do
      input_stream =
        Stream.map(
          [
            %{content: "valid", metadata: nil},
            %{content: "with_extra", metadata: nil, some_extra_key: "ignored"}
          ],
          & &1
        )

      result_stream = LLMClient.stream_to_structs(input_stream, @streamable_schema)
      results = Enum.to_list(result_stream)

      assert length(results) == 2
      assert %{content: "valid", metadata: nil} = Enum.at(results, 0)
      assert %{content: "with_extra", metadata: nil} = Enum.at(results, 1)
    end
  end

  describe "stream_to_structs/2 with function streams" do
    test "handles function-based stream (arity 2)" do
      stream_fn = fn acc, fun ->
        fun.({:cont, %{"content" => "from_fn"}}, acc)
      end

      result = LLMClient.stream_to_structs(stream_fn, @streamable_schema)

      assert is_struct(result, Stream) or is_function(result, 2)
    end
  end

  describe "stream_to_structs/2 with map chunks" do
    test "passes through chunks that are already validated" do
      existing_map = %{content: "already", metadata: nil}
      input_stream = Stream.map([existing_map], & &1)

      result_stream = LLMClient.stream_to_structs(input_stream, @streamable_schema)
      results = Enum.to_list(result_stream)

      assert length(results) == 1
      assert %{content: "already", metadata: nil} = hd(results)
    end

    test "converts maps with string keys" do
      other_map = %{"content" => "convert_me", "metadata" => nil}
      input_stream = Stream.map([other_map], & &1)

      result_stream = LLMClient.stream_to_structs(input_stream, @streamable_schema)
      results = Enum.to_list(result_stream)

      assert length(results) == 1
      assert %{content: "convert_me"} = hd(results)
    end
  end

  describe "stream_to_structs/2 with partial/progressive chunks" do
    test "handles progressive building of response" do
      input_stream =
        Stream.map(
          [
            %{"text" => nil, "complete" => false},
            %{"text" => "partial", "complete" => false},
            %{"text" => "final result", "complete" => true}
          ],
          & &1
        )

      result_stream = LLMClient.stream_to_structs(input_stream, @partial_schema)
      results = Enum.to_list(result_stream)

      assert length(results) == 3
      assert %{text: nil, complete: false} = Enum.at(results, 0)
      assert %{text: "partial", complete: false} = Enum.at(results, 1)
      assert %{text: "final result", complete: true} = Enum.at(results, 2)
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
          input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
          output_schema(Zoi.object(%{content: Zoi.string()}, coerce: true))
          instruction("test")
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
        |> LLMClient.stream_to_structs(@streamable_schema)
        |> Stream.filter(fn map -> map.content != "skip" end)

      results = Enum.to_list(result_stream)

      assert length(results) == 2
      assert Enum.all?(results, fn r -> r.content != "skip" end)
    end

    test "can be composed with Stream.map" do
      input_stream = Stream.map([%{"content" => "hello", "metadata" => nil}], & &1)

      result_stream =
        input_stream
        |> LLMClient.stream_to_structs(@streamable_schema)
        |> Stream.map(fn map -> String.upcase(map.content) end)

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
        |> LLMClient.stream_to_structs(@streamable_schema)
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
        |> LLMClient.stream_to_structs(@streamable_schema)
        |> Enum.reduce("", fn map, acc -> acc <> map.content end)

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

      result_stream = LLMClient.stream_to_structs(input_stream, @streamable_schema)
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

      result_stream = LLMClient.stream_to_structs(input_stream, @streamable_schema)

      results = Enum.to_list(result_stream)

      assert length(results) == 5
    end

    test "handles stream with only nil values" do
      input_stream = Stream.map([nil, nil, nil], & &1)

      result_stream = LLMClient.stream_to_structs(input_stream, @streamable_schema)
      results = Enum.to_list(result_stream)

      assert length(results) == 3
    end

    test "handles stream with empty maps" do
      input_stream = Stream.map([%{}, %{}, %{}], & &1)

      result_stream = LLMClient.stream_to_structs(input_stream, @streamable_schema)
      results = Enum.to_list(result_stream)

      assert length(results) == 3
    end

    test "handles stream with nested map content" do
      input_stream =
        Stream.map(
          [
            %{"content" => "test", "metadata" => %{"nested" => %{"deep" => "value"}}}
          ],
          & &1
        )

      result_stream = LLMClient.stream_to_structs(input_stream, @streamable_schema)
      results = Enum.to_list(result_stream)

      assert length(results) == 1

      assert %{content: "test", metadata: %{"nested" => %{"deep" => "value"}}} = hd(results)
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

      result_stream = LLMClient.stream_to_structs(input_stream, @streamable_schema)
      results = Enum.to_list(result_stream)

      assert length(results) == 3
      assert Enum.at(results, 0).content == "Hello 世界 🌍"
      assert Enum.at(results, 1).content == "Élève résumé"
      assert Enum.at(results, 2).content == "日本語テスト"
    end

    test "handles stream with very long content strings" do
      long_content = String.duplicate("a", 100_000)
      input_stream = Stream.map([%{"content" => long_content}], & &1)

      result_stream = LLMClient.stream_to_structs(input_stream, @streamable_schema)
      results = Enum.to_list(result_stream)

      assert length(results) == 1
      assert String.length(hd(results).content) == 100_000
    end

    test "handles rapid sequential consumption" do
      input_stream =
        Stream.map(1..100, fn i ->
          %{"content" => "item_#{i}"}
        end)

      result_stream = LLMClient.stream_to_structs(input_stream, @streamable_schema)

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

      result_stream = LLMClient.stream_to_structs(input_stream, @streamable_schema)
      results = Enum.to_list(result_stream)

      valid_results =
        Enum.filter(results, &match?(%{content: c} when c != nil, &1))

      assert length(valid_results) == 2
    end

    test "handles map with missing optional field gracefully" do
      input_stream = Stream.map([%{"metadata" => %{"key" => "value"}}], & &1)

      result_stream = LLMClient.stream_to_structs(input_stream, @streamable_schema)
      results = Enum.to_list(result_stream)

      assert length(results) == 1
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

      result_stream = LLMClient.stream_to_structs(input_stream, @streamable_schema)
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

      result_stream = LLMClient.stream_to_structs(input_stream, @streamable_schema)

      assert :counters.get(call_count, 1) == 0

      _first_10 = Enum.take(result_stream, 10)

      assert :counters.get(call_count, 1) == 10
    end

    test "supports infinite streams with take" do
      infinite_stream =
        Stream.iterate(0, &(&1 + 1))
        |> Stream.map(fn i -> %{"content" => "item_#{i}"} end)

      result_stream = LLMClient.stream_to_structs(infinite_stream, @streamable_schema)

      results = Enum.take(result_stream, 5)

      assert length(results) == 5
      assert Enum.at(results, 0).content == "item_0"
      assert Enum.at(results, 4).content == "item_4"
    end
  end
end
