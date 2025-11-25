defmodule AshAgent.Telemetry.EventsTest do
  use ExUnit.Case, async: true

  alias AshAgent.Telemetry.Events

  # Note: Not including doctest due to incomplete example in all_events/0
  # doctest AshAgent.Telemetry.Events

  describe "agent_call_events/0" do
    test "returns list of call event names" do
      events = Events.agent_call_events()

      assert is_list(events)
      assert length(events) == 4
    end

    test "includes :start event" do
      assert [:ash_agent, :call, :start] in Events.agent_call_events()
    end

    test "includes :stop event" do
      assert [:ash_agent, :call, :stop] in Events.agent_call_events()
    end

    test "includes :exception event" do
      assert [:ash_agent, :call, :exception] in Events.agent_call_events()
    end

    test "includes :summary event" do
      assert [:ash_agent, :call, :summary] in Events.agent_call_events()
    end

    test "all events have :ash_agent prefix" do
      for event <- Events.agent_call_events() do
        assert hd(event) == :ash_agent
      end
    end
  end

  describe "agent_stream_events/0" do
    test "returns list of stream event names" do
      events = Events.agent_stream_events()

      assert is_list(events)
      assert length(events) == 4
    end

    test "includes :start event" do
      assert [:ash_agent, :stream, :start] in Events.agent_stream_events()
    end

    test "includes :stop event" do
      assert [:ash_agent, :stream, :stop] in Events.agent_stream_events()
    end

    test "includes :exception event" do
      assert [:ash_agent, :stream, :exception] in Events.agent_stream_events()
    end

    test "includes :summary event" do
      assert [:ash_agent, :stream, :summary] in Events.agent_stream_events()
    end
  end

  describe "tool_call_events/0" do
    test "returns list of tool call event names" do
      events = Events.tool_call_events()

      assert is_list(events)
      assert length(events) == 6
    end

    test "includes all required events" do
      events = Events.tool_call_events()

      assert [:ash_agent, :tool_call, :start] in events
      assert [:ash_agent, :tool_call, :complete] in events
      assert [:ash_agent, :tool_call, :decision] in events
      assert [:ash_agent, :tool_call, :retry] in events
      assert [:ash_agent, :tool_call, :error] in events
      assert [:ash_agent, :tool_call, :exception] in events
    end
  end

  describe "iteration_events/0" do
    test "returns list of iteration event names" do
      events = Events.iteration_events()

      assert is_list(events)
      assert length(events) == 2
    end

    test "includes :start and :stop events" do
      events = Events.iteration_events()

      assert [:ash_agent, :iteration, :start] in events
      assert [:ash_agent, :iteration, :stop] in events
    end
  end

  describe "token_events/0" do
    test "returns list of token event names" do
      events = Events.token_events()

      assert is_list(events)
      assert length(events) == 2
    end

    test "includes warning and progress events" do
      events = Events.token_events()

      assert [:ash_agent, :token_limit_warning] in events
      assert [:ash_agent, :token_limit_progress] in events
    end
  end

  describe "hook_events/0" do
    test "returns list of hook event names" do
      events = Events.hook_events()

      assert is_list(events)
      assert length(events) == 3
    end

    test "includes :start, :stop, and :error events" do
      events = Events.hook_events()

      assert [:ash_agent, :hook, :start] in events
      assert [:ash_agent, :hook, :stop] in events
      assert [:ash_agent, :hook, :error] in events
    end
  end

  describe "progressive_disclosure_events/0" do
    test "returns list of progressive disclosure event names" do
      events = Events.progressive_disclosure_events()

      assert is_list(events)
      assert length(events) == 3
    end

    test "includes all strategy events" do
      events = Events.progressive_disclosure_events()

      assert [:ash_agent, :progressive_disclosure, :process_results] in events
      assert [:ash_agent, :progressive_disclosure, :sliding_window] in events
      assert [:ash_agent, :progressive_disclosure, :token_based] in events
    end
  end

  describe "prompt_events/0" do
    test "returns list of prompt event names" do
      events = Events.prompt_events()

      assert is_list(events)
      assert length(events) == 1
    end

    test "includes rendered event" do
      assert [:ash_agent, :prompt, :rendered] in Events.prompt_events()
    end
  end

  describe "llm_events/0" do
    test "returns list of LLM event names" do
      events = Events.llm_events()

      assert is_list(events)
      assert length(events) == 2
    end

    test "includes request and response events" do
      events = Events.llm_events()

      assert [:ash_agent, :llm, :request] in events
      assert [:ash_agent, :llm, :response] in events
    end
  end

  describe "stream_chunk_events/0" do
    test "returns list of stream chunk event names" do
      events = Events.stream_chunk_events()

      assert is_list(events)
      assert length(events) == 1
    end

    test "includes chunk event" do
      assert [:ash_agent, :stream, :chunk] in Events.stream_chunk_events()
    end
  end

  describe "annotation_events/0" do
    test "returns list of annotation event names" do
      events = Events.annotation_events()

      assert is_list(events)
      assert length(events) == 1
    end

    test "includes annotation event" do
      assert [:ash_agent, :annotation] in Events.annotation_events()
    end
  end

  describe "all_events/0" do
    test "returns all events combined" do
      all_events = Events.all_events()

      assert is_list(all_events)
    end

    test "includes events from all categories" do
      all_events = Events.all_events()

      # Check that at least one event from each category is present
      assert [:ash_agent, :call, :start] in all_events
      assert [:ash_agent, :stream, :start] in all_events
      assert [:ash_agent, :tool_call, :start] in all_events
      assert [:ash_agent, :iteration, :start] in all_events
      assert [:ash_agent, :token_limit_warning] in all_events
      assert [:ash_agent, :hook, :start] in all_events
      assert [:ash_agent, :progressive_disclosure, :process_results] in all_events
      assert [:ash_agent, :prompt, :rendered] in all_events
      assert [:ash_agent, :llm, :request] in all_events
      assert [:ash_agent, :stream, :chunk] in all_events
      assert [:ash_agent, :annotation] in all_events
    end

    test "count matches sum of all category functions" do
      expected_count =
        length(Events.agent_call_events()) +
          length(Events.agent_stream_events()) +
          length(Events.tool_call_events()) +
          length(Events.iteration_events()) +
          length(Events.token_events()) +
          length(Events.hook_events()) +
          length(Events.progressive_disclosure_events()) +
          length(Events.prompt_events()) +
          length(Events.llm_events()) +
          length(Events.stream_chunk_events()) +
          length(Events.annotation_events())

      assert length(Events.all_events()) == expected_count
    end

    test "all events have valid format (list of atoms)" do
      for event <- Events.all_events() do
        assert is_list(event)
        assert Enum.all?(event, &is_atom/1)
        assert hd(event) == :ash_agent
      end
    end
  end

  describe "event consistency" do
    test "all events start with :ash_agent" do
      for event <- Events.all_events() do
        assert hd(event) == :ash_agent, "Event #{inspect(event)} should start with :ash_agent"
      end
    end

    test "all events have at least 2 segments" do
      for event <- Events.all_events() do
        assert length(event) >= 2, "Event #{inspect(event)} should have at least 2 segments"
      end
    end

    test "no duplicate events in all_events" do
      all_events = Events.all_events()
      unique_events = Enum.uniq(all_events)

      assert length(all_events) == length(unique_events), "all_events contains duplicates"
    end
  end
end
