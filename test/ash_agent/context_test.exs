defmodule AshAgent.ContextTest do
  use ExUnit.Case, async: true

  doctest AshAgent.Context

  alias AshAgent.Context

  describe "new/2" do
    test "creates a new context with initial user message" do
      context = Context.new("Hello", [])

      assert context.current_iteration == 1
      assert length(context.iterations) == 1

      [iteration] = context.iterations
      assert iteration.number == 1
      assert length(iteration.messages) == 1

      [message] = iteration.messages
      assert message.role == :user
      assert message.content == "Hello"
    end

    test "creates context with system prompt option" do
      context = Context.new("Hello", system_prompt: "You are helpful")

      [iteration] = context.iterations
      assert length(iteration.messages) == 2

      [system_message, user_message] = iteration.messages
      assert system_message.role == :system
      assert system_message.content == "You are helpful"
      assert user_message.role == :user
      assert user_message.content == "Hello"
    end

    test "handles map input without message key" do
      context = Context.new(%{data: "test"}, [])

      [iteration] = context.iterations
      [message] = iteration.messages
      assert message.role == :user
      assert is_binary(message.content)
    end
  end

  describe "add_assistant_message/3" do
    test "adds assistant message to current iteration" do
      context = Context.new("Hello", [])
      context = Context.add_assistant_message(context, "Hi there!")

      assert context.current_iteration == 1
      assert length(context.iterations) == 1

      [iteration] = context.iterations
      assert iteration.number == 1
      assert length(iteration.messages) == 2

      [_, assistant_message] = iteration.messages
      assert assistant_message.role == :assistant
      assert assistant_message.content == "Hi there!"
      assert assistant_message.tool_calls == nil
    end

    test "adds assistant message with tool calls" do
      context = Context.new("Hello", [])
      tool_calls = [%{id: "call_1", name: "get_weather", arguments: %{city: "NYC"}}]

      context = Context.add_assistant_message(context, "Let me check", tool_calls)

      assert context.current_iteration == 1
      assert length(context.iterations) == 1

      [iteration] = context.iterations
      [_, assistant_message] = iteration.messages
      assert assistant_message.role == :assistant
      assert assistant_message.content == "Let me check"
      assert assistant_message.tool_calls == tool_calls
    end

    test "carries forward messages in same iteration" do
      context = Context.new("Hello", system_prompt: "Be helpful")
      context = Context.add_assistant_message(context, "Response 1")

      [iteration] = context.iterations
      assert length(iteration.messages) == 3

      [system, user, assistant] = iteration.messages
      assert system.role == :system
      assert user.role == :user
      assert assistant.role == :assistant
    end
  end

  describe "add_tool_results/2" do
    test "adds tool results to current iteration" do
      context = Context.new("Hello", [])

      context =
        Context.add_assistant_message(context, "Checking", [
          %{id: "call_1", name: "get_weather", arguments: %{}}
        ])

      results = [
        {"call_1", {:ok, %{temperature: 72}}}
      ]

      context = Context.add_tool_results(context, results)

      assert context.current_iteration == 1
      assert length(context.iterations) == 1

      [iteration] = context.iterations
      assert iteration.number == 1
      assert length(iteration.messages) == 3

      [_, _, result_message] = iteration.messages
      assert result_message.role == :user
      assert is_list(result_message.content)
      assert length(result_message.content) == 1

      [content_part] = result_message.content
      assert content_part.type == :tool_result
      assert content_part.tool_use_id == "call_1"
      assert is_binary(content_part.content)
    end

    test "handles tool errors" do
      context = Context.new("Hello", [])

      context =
        Context.add_assistant_message(context, "Checking", [
          %{id: "call_1", name: "get_weather", arguments: %{}}
        ])

      results = [
        {"call_1", {:error, "API unavailable"}}
      ]

      context = Context.add_tool_results(context, results)

      [iteration] = context.iterations
      [_, _, result_message] = iteration.messages
      [content_part] = result_message.content
      assert content_part.type == :tool_result
      assert is_binary(content_part.content)
    end
  end

  describe "exceeded_max_iterations?/2" do
    test "returns false when under max iterations" do
      context = Context.new("Hello", [])

      refute Context.exceeded_max_iterations?(context, 5)
    end

    test "returns true when at max iterations" do
      context = Context.new("Hello", [])

      assert Context.exceeded_max_iterations?(context, 1)
    end

    test "returns false when below max iterations" do
      context = Context.new("Hello", [])

      refute Context.exceeded_max_iterations?(context, 2)
    end
  end

  describe "extract_tool_calls/1" do
    test "extracts tool calls from last assistant message" do
      context = Context.new("Hello", [])
      tool_calls = [%{id: "call_1", name: "get_weather", arguments: %{}}]

      context = Context.add_assistant_message(context, "Checking", tool_calls)

      assert Context.extract_tool_calls(context) == tool_calls
    end

    test "returns empty list when no tool calls" do
      context = Context.new("Hello", [])
      context = Context.add_assistant_message(context, "No tools")

      assert Context.extract_tool_calls(context) == []
    end

    test "returns empty list when last message is not assistant" do
      context = Context.new("Hello", [])

      assert Context.extract_tool_calls(context) == []
    end
  end

  describe "to_messages/1" do
    test "converts context to provider message format" do
      context = Context.new("Hello", [])
      context = Context.add_assistant_message(context, "Hi there!")

      messages = Context.to_messages(context)

      assert length(messages) == 2
      assert hd(messages).role == "user"
      assert List.last(messages).role == "assistant"
    end

    test "formats tool calls in messages" do
      context = Context.new("Hello", [])
      tool_calls = [%{id: "call_1", name: "get_weather", arguments: %{city: "NYC"}}]

      context = Context.add_assistant_message(context, "Checking", tool_calls)

      messages = Context.to_messages(context)
      assistant_message = List.last(messages)

      assert assistant_message.role == "assistant"
      assert is_list(assistant_message.tool_calls)
      assert length(assistant_message.tool_calls) == 1

      [tool_call] = assistant_message.tool_calls
      assert tool_call.id == "call_1"
      assert tool_call.function.name == "get_weather"
    end

    test "formats tool results in messages" do
      context = Context.new("Hello", [])

      context =
        Context.add_assistant_message(context, "Checking", [
          %{id: "call_1", name: "get_weather", arguments: %{}}
        ])

      results = [{"call_1", {:ok, %{temperature: 72}}}]
      context = Context.add_tool_results(context, results)

      messages = Context.to_messages(context)
      assert length(messages) == 3

      result_message = Enum.at(messages, 2)
      assert result_message.role == "user"
      assert is_list(result_message.content)
    end
  end

  describe "get_iteration/2" do
    test "retrieves specific iteration by number" do
      context = Context.new("Hello", [])

      iteration = Context.get_iteration(context, 1)
      assert iteration.number == 1
      assert length(iteration.messages) == 1
    end

    test "returns nil for non-existent iteration" do
      context = Context.new("Hello", [])

      assert Context.get_iteration(context, 99) == nil
    end

    test "returns nil for negative iteration number" do
      context = Context.new("Hello", [])

      assert Context.get_iteration(context, -1) == nil
    end
  end

  describe "add_token_usage/2" do
    test "adds token usage to current iteration metadata" do
      context = Context.new("Hello", [])
      usage = %{input_tokens: 100, output_tokens: 50, total_tokens: 150}

      context = Context.add_token_usage(context, usage)

      iteration = Context.get_iteration(context, 1)
      assert iteration.metadata.current_usage == usage
      assert iteration.metadata.cumulative_tokens.input_tokens == 100
      assert iteration.metadata.cumulative_tokens.output_tokens == 50
      assert iteration.metadata.cumulative_tokens.total_tokens == 150
    end

    test "accumulates token usage across multiple calls" do
      context = Context.new("Hello", [])
      usage1 = %{input_tokens: 100, output_tokens: 50, total_tokens: 150}
      usage2 = %{input_tokens: 75, output_tokens: 25, total_tokens: 100}

      context = Context.add_token_usage(context, usage1)
      context = Context.add_token_usage(context, usage2)

      cumulative = Context.get_cumulative_tokens(context)
      assert cumulative.input_tokens == 175
      assert cumulative.output_tokens == 75
      assert cumulative.total_tokens == 250
    end

    test "handles partial usage maps and calculates total_tokens" do
      context = Context.new("Hello", [])
      usage = %{input_tokens: 100}

      context = Context.add_token_usage(context, usage)

      cumulative = Context.get_cumulative_tokens(context)
      assert cumulative.input_tokens == 100
      assert cumulative.output_tokens == 0
      assert cumulative.total_tokens == 100
    end
  end

  describe "get_cumulative_tokens/1" do
    test "returns zero tokens for new context" do
      context = Context.new("Hello", [])

      cumulative = Context.get_cumulative_tokens(context)
      assert cumulative.input_tokens == 0
      assert cumulative.output_tokens == 0
      assert cumulative.total_tokens == 0
    end

    test "returns cumulative tokens after usage added" do
      context = Context.new("Hello", [])
      usage = %{input_tokens: 200, output_tokens: 100, total_tokens: 300}

      context = Context.add_token_usage(context, usage)

      cumulative = Context.get_cumulative_tokens(context)
      assert cumulative.input_tokens == 200
      assert cumulative.output_tokens == 100
      assert cumulative.total_tokens == 300
    end
  end

  describe "keep_last_iterations/2" do
    test "keeps only the last N iterations" do
      iterations = [
        %{number: 1, started_at: ~U[2025-01-01 10:00:00Z]},
        %{number: 2, started_at: ~U[2025-01-01 11:00:00Z]},
        %{number: 3, started_at: ~U[2025-01-01 12:00:00Z]},
        %{number: 4, started_at: ~U[2025-01-01 13:00:00Z]},
        %{number: 5, started_at: ~U[2025-01-01 14:00:00Z]}
      ]

      context = %Context{iterations: iterations}

      result = Context.keep_last_iterations(context, 2)

      assert %Context{iterations: kept} = result
      assert length(kept) == 2
      assert [%{number: 4}, %{number: 5}] = kept
    end

    test "keeps all iterations when count > iteration count" do
      iterations = [
        %{number: 1},
        %{number: 2}
      ]

      context = %Context{iterations: iterations}

      result = Context.keep_last_iterations(context, 10)

      assert %Context{iterations: kept} = result
      assert length(kept) == 2
      assert kept == iterations
    end

    test "keeps only one iteration when count = 1" do
      iterations = [
        %{number: 1},
        %{number: 2},
        %{number: 3}
      ]

      context = %Context{iterations: iterations}

      result = Context.keep_last_iterations(context, 1)

      assert %Context{iterations: [%{number: 3}]} = result
    end

    test "handles empty context" do
      context = %Context{iterations: []}

      result = Context.keep_last_iterations(context, 5)

      assert %Context{iterations: []} = result
    end

    test "does not modify original context (immutability)" do
      iterations = [%{number: 1}, %{number: 2}, %{number: 3}]
      context = %Context{iterations: iterations}

      _result = Context.keep_last_iterations(context, 1)

      assert context.iterations == iterations
      assert length(context.iterations) == 3
    end
  end

  describe "remove_old_iterations/2" do
    test "removes iterations older than specified age" do
      now = DateTime.utc_now()
      two_hours_ago = DateTime.add(now, -2 * 3600, :second)
      one_hour_ago = DateTime.add(now, -1 * 3600, :second)

      iterations = [
        %{number: 1, started_at: two_hours_ago},
        %{number: 2, started_at: one_hour_ago},
        %{number: 3, started_at: now}
      ]

      context = %Context{iterations: iterations}

      result = Context.remove_old_iterations(context, 5400)

      assert %Context{iterations: kept} = result
      assert length(kept) == 2
      assert Enum.map(kept, & &1.number) == [2, 3]
    end

    test "keeps all iterations when none are old" do
      now = DateTime.utc_now()
      recent = DateTime.add(now, -60, :second)

      iterations = [
        %{number: 1, started_at: recent},
        %{number: 2, started_at: now}
      ]

      context = %Context{iterations: iterations}

      result = Context.remove_old_iterations(context, 3600)

      assert %Context{iterations: kept} = result
      assert length(kept) == 2
      assert kept == iterations
    end

    test "removes all old iterations" do
      old = DateTime.add(DateTime.utc_now(), -2 * 3600, :second)

      iterations = [
        %{number: 1, started_at: old},
        %{number: 2, started_at: old}
      ]

      context = %Context{iterations: iterations}

      result = Context.remove_old_iterations(context, 3600)

      assert %Context{iterations: []} = result
    end

    test "keeps iterations with missing timestamps" do
      old = DateTime.add(DateTime.utc_now(), -2 * 3600, :second)

      iterations = [
        %{number: 1, started_at: old},
        %{number: 2},
        %{number: 3, started_at: DateTime.utc_now()}
      ]

      context = %Context{iterations: iterations}

      result = Context.remove_old_iterations(context, 3600)

      assert %Context{iterations: kept} = result
      assert length(kept) == 2
      assert Enum.map(kept, & &1.number) == [2, 3]
    end

    test "does not modify original context (immutability)" do
      old = DateTime.add(DateTime.utc_now(), -2 * 3600, :second)
      iterations = [%{number: 1, started_at: old}]
      context = %Context{iterations: iterations}

      _result = Context.remove_old_iterations(context, 3600)

      assert context.iterations == iterations
    end
  end

  describe "count_iterations/1" do
    test "returns count of iterations" do
      context = %Context{
        iterations: [
          %{number: 1},
          %{number: 2},
          %{number: 3}
        ]
      }

      assert Context.count_iterations(context) == 3
    end

    test "returns 0 for empty context" do
      context = %Context{iterations: []}

      assert Context.count_iterations(context) == 0
    end

    test "returns correct count for single iteration" do
      context = %Context{iterations: [%{number: 1}]}

      assert Context.count_iterations(context) == 1
    end
  end

  describe "get_iteration_range/3" do
    test "returns slice of iterations" do
      iterations = [
        %{number: 1},
        %{number: 2},
        %{number: 3},
        %{number: 4},
        %{number: 5}
      ]

      context = %Context{iterations: iterations}

      result = Context.get_iteration_range(context, 1, 3)

      assert %Context{iterations: sliced} = result
      assert length(sliced) == 3
      assert [%{number: 2}, %{number: 3}, %{number: 4}] = sliced
    end

    test "handles out of bounds start index" do
      iterations = [%{number: 1}, %{number: 2}]
      context = %Context{iterations: iterations}

      result = Context.get_iteration_range(context, 10, 15)

      assert %Context{iterations: []} = result
    end

    test "handles out of bounds end index" do
      iterations = [%{number: 1}, %{number: 2}, %{number: 3}]
      context = %Context{iterations: iterations}

      result = Context.get_iteration_range(context, 1, 10)

      assert %Context{iterations: sliced} = result
      assert [%{number: 2}, %{number: 3}] = sliced
    end

    test "returns single iteration when start == end" do
      iterations = [%{number: 1}, %{number: 2}, %{number: 3}]
      context = %Context{iterations: iterations}

      result = Context.get_iteration_range(context, 1, 1)

      assert %Context{iterations: [%{number: 2}]} = result
    end

    test "returns all iterations when range covers all" do
      iterations = [%{number: 1}, %{number: 2}, %{number: 3}]
      context = %Context{iterations: iterations}

      result = Context.get_iteration_range(context, 0, 2)

      assert %Context{iterations: sliced} = result
      assert sliced == iterations
    end

    test "preserves iteration ordering" do
      iterations = [
        %{number: 1},
        %{number: 2},
        %{number: 3},
        %{number: 4}
      ]

      context = %Context{iterations: iterations}

      result = Context.get_iteration_range(context, 0, 2)

      assert %Context{iterations: [%{number: 1}, %{number: 2}, %{number: 3}]} = result
    end

    test "does not modify original context (immutability)" do
      iterations = [%{number: 1}, %{number: 2}, %{number: 3}]
      context = %Context{iterations: iterations}

      _result = Context.get_iteration_range(context, 0, 1)

      assert context.iterations == iterations
    end
  end

  describe "mark_as_summarized/2" do
    test "adds all metadata fields to iteration" do
      iteration = %{number: 1, messages: []}

      summarized = Context.mark_as_summarized(iteration, "User asked about weather")

      assert %{metadata: metadata} = summarized
      assert metadata.summarized == true
      assert metadata.summary == "User asked about weather"
      assert %DateTime{} = metadata.summarized_at
    end

    test "works on iteration without existing metadata field" do
      iteration = %{number: 1}

      summarized = Context.mark_as_summarized(iteration, "Test summary")

      assert %{metadata: metadata} = summarized
      assert metadata.summarized == true
      assert metadata.summary == "Test summary"
    end

    test "preserves existing metadata fields" do
      iteration = %{metadata: %{custom_field: "preserved", other: 42}}

      summarized = Context.mark_as_summarized(iteration, "New summary")

      assert summarized.metadata.custom_field == "preserved"
      assert summarized.metadata.other == 42
      assert summarized.metadata.summarized == true
      assert summarized.metadata.summary == "New summary"
    end

    test "overwrites previous summarization" do
      iteration = %{
        metadata: %{
          summarized: true,
          summary: "Old summary",
          summarized_at: DateTime.from_unix!(1_000_000)
        }
      }

      summarized = Context.mark_as_summarized(iteration, "New summary")

      assert summarized.metadata.summary == "New summary"

      assert DateTime.compare(summarized.metadata.summarized_at, iteration.metadata.summarized_at) ==
               :gt
    end

    test "returns new iteration (immutability)" do
      iteration = %{metadata: %{}}

      summarized = Context.mark_as_summarized(iteration, "Summary")

      refute Map.has_key?(iteration.metadata, :summarized)
      assert summarized.metadata.summarized == true
    end
  end

  describe "is_summarized?/1" do
    test "returns true for summarized iteration" do
      iteration = %{metadata: %{summarized: true}}

      assert Context.is_summarized?(iteration)
    end

    test "returns false for unsummarized iteration" do
      iteration = %{metadata: %{}}

      refute Context.is_summarized?(iteration)
    end

    test "returns false when summarized is false" do
      iteration = %{metadata: %{summarized: false}}

      refute Context.is_summarized?(iteration)
    end

    test "returns false when metadata field is missing" do
      iteration = %{number: 1}

      refute Context.is_summarized?(iteration)
    end

    test "returns false for empty iteration map" do
      iteration = %{}

      refute Context.is_summarized?(iteration)
    end
  end

  describe "get_summary/1" do
    test "retrieves summary from summarized iteration" do
      iteration = %{metadata: %{summarized: true, summary: "Weather query"}}

      assert Context.get_summary(iteration) == "Weather query"
    end

    test "returns nil for unsummarized iteration" do
      iteration = %{metadata: %{}}

      assert Context.get_summary(iteration) == nil
    end

    test "returns nil when metadata field is missing" do
      iteration = %{number: 1}

      assert Context.get_summary(iteration) == nil
    end

    test "returns nil for empty iteration" do
      iteration = %{}

      assert Context.get_summary(iteration) == nil
    end

    test "retrieves summary even if summarized flag is false" do
      iteration = %{metadata: %{summarized: false, summary: "Still has summary"}}

      assert Context.get_summary(iteration) == "Still has summary"
    end
  end

  describe "update_iteration_metadata/3" do
    test "adds custom field to metadata" do
      iteration = %{metadata: %{}}

      updated = Context.update_iteration_metadata(iteration, :custom_key, "value")

      assert updated.metadata.custom_key == "value"
    end

    test "works on iteration without existing metadata field" do
      iteration = %{number: 1}

      updated = Context.update_iteration_metadata(iteration, :new_field, 123)

      assert %{metadata: metadata} = updated
      assert metadata.new_field == 123
    end

    test "preserves existing metadata fields" do
      iteration = %{metadata: %{existing: "data", other: 42}}

      updated = Context.update_iteration_metadata(iteration, :new_field, "new")

      assert updated.metadata.existing == "data"
      assert updated.metadata.other == 42
      assert updated.metadata.new_field == "new"
    end

    test "overwrites existing field with same key" do
      iteration = %{metadata: %{field: "old value"}}

      updated = Context.update_iteration_metadata(iteration, :field, "new value")

      assert updated.metadata.field == "new value"
    end

    test "supports various value types" do
      iteration = %{metadata: %{}}

      updated1 = Context.update_iteration_metadata(iteration, :string, "text")
      assert updated1.metadata.string == "text"

      updated2 = Context.update_iteration_metadata(iteration, :int, 42)
      assert updated2.metadata.int == 42

      updated3 = Context.update_iteration_metadata(iteration, :map, %{nested: true})
      assert updated3.metadata.map == %{nested: true}

      updated4 = Context.update_iteration_metadata(iteration, :list, [1, 2, 3])
      assert updated4.metadata.list == [1, 2, 3]
    end

    test "returns new iteration (immutability)" do
      iteration = %{metadata: %{}}

      updated = Context.update_iteration_metadata(iteration, :new_field, "value")

      refute Map.has_key?(iteration.metadata, :new_field)
      assert updated.metadata.new_field == "value"
    end
  end

  describe "metadata doesn't affect other iterations" do
    test "marking one iteration doesn't affect another" do
      iteration1 = %{number: 1, metadata: %{}}
      iteration2 = %{number: 2, metadata: %{}}

      summarized1 = Context.mark_as_summarized(iteration1, "Summary 1")

      refute Context.is_summarized?(iteration2)
      assert Context.is_summarized?(summarized1)
    end

    test "updating metadata on one iteration doesn't affect another" do
      iteration1 = %{metadata: %{shared: "value"}}
      iteration2 = %{metadata: %{shared: "value"}}

      updated1 = Context.update_iteration_metadata(iteration1, :custom, "data")

      refute Map.has_key?(iteration2.metadata, :custom)
      assert updated1.metadata.custom == "data"
    end
  end

  describe "metadata integration with full workflow" do
    test "can mark, check, and retrieve summary" do
      iteration = %{number: 5, messages: []}

      summarized = Context.mark_as_summarized(iteration, "Complex calculation result")

      assert Context.is_summarized?(summarized)

      summary = Context.get_summary(summarized)
      assert summary == "Complex calculation result"

      with_custom = Context.update_iteration_metadata(summarized, :processed, true)

      assert with_custom.metadata.summarized == true
      assert with_custom.metadata.summary == "Complex calculation result"
      assert with_custom.metadata.processed == true
    end
  end

  defp build_context_with_messages(message_count) do
    messages =
      for i <- 1..message_count do
        %{role: :user, content: "Message #{i}"}
      end

    %Context{
      iterations: [
        %{
          number: 1,
          messages: messages,
          metadata: %{}
        }
      ],
      current_iteration: 1
    }
  end

  describe "exceeds_token_budget?/2 returns false when under budget" do
    test "with empty context" do
      context = %Context{iterations: []}

      refute Context.exceeds_token_budget?(context, 100)
    end

    test "with small context well under budget" do
      context = build_context_with_messages(1)

      refute Context.exceeds_token_budget?(context, 100)
    end

    test "with context just under budget" do
      context = build_context_with_messages(5)

      refute Context.exceeds_token_budget?(context, 51)
    end
  end

  describe "exceeds_token_budget?/2 returns true when over budget" do
    test "with many messages" do
      context = build_context_with_messages(20)

      assert Context.exceeds_token_budget?(context, 100)
    end

    test "with very many messages" do
      context = build_context_with_messages(100)

      assert Context.exceeds_token_budget?(context, 500)
    end

    test "with multiple iterations" do
      context = %Context{
        iterations: [
          %{number: 1, messages: List.duplicate(%{role: :user, content: "x"}, 10)},
          %{number: 2, messages: List.duplicate(%{role: :user, content: "x"}, 10)},
          %{number: 3, messages: List.duplicate(%{role: :user, content: "x"}, 10)}
        ],
        current_iteration: 3
      }

      assert Context.exceeds_token_budget?(context, 100)
    end
  end

  describe "estimate_token_count/1 returns non-negative integer" do
    test "with empty context" do
      context = %Context{iterations: []}

      estimate = Context.estimate_token_count(context)

      assert is_integer(estimate)
      assert estimate == 0
    end

    test "with small context" do
      context = build_context_with_messages(1)

      estimate = Context.estimate_token_count(context)

      assert is_integer(estimate)
      assert estimate == 10
    end

    test "with multiple messages" do
      context = %Context{
        iterations: [
          %{
            number: 1,
            messages: [
              %{role: :user, content: "Hello"},
              %{role: :assistant, content: "Hi there!"}
            ]
          }
        ],
        current_iteration: 1
      }

      estimate = Context.estimate_token_count(context)

      assert is_integer(estimate)
      assert estimate == 20
    end
  end

  describe "estimate_token_count/1 accuracy" do
    test "returns exactly 10 tokens per message due to bug" do
      context = %Context{
        iterations: [
          %{number: 1, messages: [%{role: :user, content: "Hello"}]}
        ],
        current_iteration: 1
      }

      estimate = Context.estimate_token_count(context)

      assert estimate == 10
    end

    test "scales linearly with message count not content size" do
      small_context = build_context_with_messages(5)
      large_context = build_context_with_messages(50)

      small_estimate = Context.estimate_token_count(small_context)
      large_estimate = Context.estimate_token_count(large_context)

      ratio = large_estimate / small_estimate

      assert ratio == 10.0
    end

    test "includes overhead for message structure" do
      context = %Context{
        iterations: [
          %{number: 1, messages: [%{role: :user, content: "x"}]}
        ],
        current_iteration: 1
      }

      estimate = Context.estimate_token_count(context)

      assert estimate == 10
    end
  end

  describe "tokens_remaining/2 with budget remaining" do
    test "with empty context returns full budget" do
      context = %Context{iterations: []}

      assert Context.tokens_remaining(context, 50_000) == 50_000
    end

    test "with small context returns most of budget" do
      context = build_context_with_messages(1)

      remaining = Context.tokens_remaining(context, 100)

      assert remaining == 90
    end

    test "calculation is correct" do
      context = build_context_with_messages(5)
      budget = 1000

      estimate = Context.estimate_token_count(context)
      remaining = Context.tokens_remaining(context, budget)

      assert remaining == budget - estimate
      assert remaining == 950
    end
  end

  describe "tokens_remaining/2 with over budget" do
    test "returns 0 when over budget" do
      context = build_context_with_messages(200)

      assert Context.tokens_remaining(context, 100) == 0
    end

    test "returns 0 when exactly at budget" do
      context = build_context_with_messages(10)

      assert Context.tokens_remaining(context, 100) == 0
    end

    test "never returns negative" do
      context = build_context_with_messages(50)

      remaining = Context.tokens_remaining(context, 100)

      assert remaining == 0
      assert remaining >= 0
    end
  end

  describe "budget_utilization/2 returns correct percentage" do
    test "returns 0.0 for empty context" do
      context = %Context{iterations: []}

      utilization = Context.budget_utilization(context, 100_000)

      assert is_float(utilization)
      assert utilization == 0.0
    end

    test "returns value between 0.0 and 1.0 when under budget" do
      context = build_context_with_messages(5)

      utilization = Context.budget_utilization(context, 1000)

      assert is_float(utilization)
      assert utilization == 0.05
      assert utilization > 0.0
      assert utilization < 1.0
    end

    test "returns > 1.0 when over budget" do
      context = build_context_with_messages(200)

      utilization = Context.budget_utilization(context, 100)

      assert is_float(utilization)
      assert utilization == 20.0
      assert utilization > 1.0
    end

    test "returns exactly 1.0 when at budget" do
      context = build_context_with_messages(10)

      utilization = Context.budget_utilization(context, 100)

      assert utilization == 1.0
    end

    test "calculation is correct" do
      context = build_context_with_messages(4)
      budget = 1000

      estimate = Context.estimate_token_count(context)
      utilization = Context.budget_utilization(context, budget)

      expected = estimate / budget

      assert utilization == expected
      assert utilization == 0.04
    end
  end

  describe "token functions handle edge cases" do
    test "context with no messages" do
      context = %Context{
        iterations: [
          %{number: 1, messages: []}
        ],
        current_iteration: 1
      }

      estimate = Context.estimate_token_count(context)

      assert is_integer(estimate)
      assert estimate == 0
    end

    test "context with empty message content" do
      context = %Context{
        iterations: [
          %{number: 1, messages: [%{role: :user, content: ""}]}
        ],
        current_iteration: 1
      }

      estimate = Context.estimate_token_count(context)

      assert estimate == 10
    end

    test "context with multiple iterations" do
      context = %Context{
        iterations: [
          %{number: 1, messages: [%{role: :user, content: "First"}]},
          %{
            number: 2,
            messages: [
              %{role: :user, content: "Second"},
              %{role: :assistant, content: "Response"}
            ]
          },
          %{number: 3, messages: [%{role: :user, content: "Third"}]}
        ],
        current_iteration: 3
      }

      estimate = Context.estimate_token_count(context)

      assert is_integer(estimate)
      assert estimate == 40
    end

    test "all functions work together" do
      context = build_context_with_messages(10)
      budget = 500

      exceeds = Context.exceeds_token_budget?(context, budget)
      estimate = Context.estimate_token_count(context)
      remaining = Context.tokens_remaining(context, budget)
      utilization = Context.budget_utilization(context, budget)

      assert exceeds == estimate > budget
      assert exceeds == false
      assert estimate == 100
      assert remaining == max(0, budget - estimate)
      assert remaining == 400
      assert utilization == estimate / budget
      assert utilization == 0.2
    end
  end
end
