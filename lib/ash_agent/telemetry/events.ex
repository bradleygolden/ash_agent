defmodule AshAgent.Telemetry.Events do
  @moduledoc """
  Defines the telemetry event schema for AshAgent.

  This module provides the canonical list of telemetry events emitted by AshAgent.
  These event names are part of the public API contract.

  ## Event Categories

  ### Agent Call Events
  Emitted during single-turn agent execution:
  - `[:ash_agent, :call, :start]` - Agent call started
  - `[:ash_agent, :call, :stop]` - Agent call completed
  - `[:ash_agent, :call, :exception]` - Agent call raised an exception
  - `[:ash_agent, :call, :summary]` - Summary metrics after call completion

  ### Agent Stream Events
  Emitted during streaming agent execution:
  - `[:ash_agent, :stream, :start]` - Stream started
  - `[:ash_agent, :stream, :stop]` - Stream completed
  - `[:ash_agent, :stream, :chunk]` - Stream chunk received
  - `[:ash_agent, :stream, :summary]` - Summary metrics after stream completion

  ### Prompt Rendering Events
  Emitted during prompt template rendering:
  - `[:ash_agent, :prompt, :rendered]` - Prompt template was rendered

  ### LLM Request Events
  Emitted during LLM provider interactions:
  - `[:ash_agent, :llm, :request]` - LLM request sent
  - `[:ash_agent, :llm, :response]` - LLM response received
  - `[:ash_agent, :llm, :error]` - LLM request failed

  ## Event Metadata

  ### Common Metadata Fields
  All events include:
  - `:agent` - The agent module name
  - `:provider` - The LLM provider (e.g., `:req_llm`, `:baml`)
  - `:client` - The client identifier
  - `:timestamp` - When the event occurred

  ### Call/Stream Stop Metadata
  - `:status` - `:ok`, `:error`, or `:unknown`
  - `:usage` - Token usage map with `:input_tokens`, `:output_tokens`, `:total_tokens`
  - `:duration` - Execution time in native time units
  - `:error` - Error struct (only on `:error` status)

  ### Prompt Rendered Metadata
  - `:prompt` - The rendered prompt string

  ### LLM Request/Response Metadata
  - `:messages` - The message history sent to the LLM
  - `:response` - The LLM response structure
  - `:schema` - JSON schema for structured output (if applicable)

  ## Usage Example

      :telemetry.attach_many(
        "my-handler",
        AshAgent.Telemetry.Events.agent_call_events(),
        &MyApp.handle_telemetry/4,
        nil
      )

      def handle_telemetry(event, measurements, metadata, _config) do
        IO.inspect({event, measurements, metadata})
      end
  """

  @doc """
  Returns all agent call-related events.

  ## Example

      iex> AshAgent.Telemetry.Events.agent_call_events()
      [
        [:ash_agent, :call, :start],
        [:ash_agent, :call, :stop],
        [:ash_agent, :call, :exception],
        [:ash_agent, :call, :summary]
      ]
  """
  @spec agent_call_events() :: [telemetry_event()]
  def agent_call_events do
    [
      [:ash_agent, :call, :start],
      [:ash_agent, :call, :stop],
      [:ash_agent, :call, :exception],
      [:ash_agent, :call, :summary]
    ]
  end

  @doc """
  Returns all agent streaming-related events.

  ## Example

      iex> AshAgent.Telemetry.Events.agent_stream_events()
      [
        [:ash_agent, :stream, :start],
        [:ash_agent, :stream, :stop],
        [:ash_agent, :stream, :chunk],
        [:ash_agent, :stream, :summary]
      ]
  """
  @spec agent_stream_events() :: [telemetry_event()]
  def agent_stream_events do
    [
      [:ash_agent, :stream, :start],
      [:ash_agent, :stream, :stop],
      [:ash_agent, :stream, :chunk],
      [:ash_agent, :stream, :summary]
    ]
  end

  @doc """
  Returns all prompt rendering events.

  ## Example

      iex> AshAgent.Telemetry.Events.prompt_events()
      [[:ash_agent, :prompt, :rendered]]
  """
  @spec prompt_events() :: [telemetry_event()]
  def prompt_events do
    [[:ash_agent, :prompt, :rendered]]
  end

  @doc """
  Returns all LLM request/response events.

  ## Example

      iex> AshAgent.Telemetry.Events.llm_events()
      [
        [:ash_agent, :llm, :request],
        [:ash_agent, :llm, :response],
        [:ash_agent, :llm, :error]
      ]
  """
  @spec llm_events() :: [telemetry_event()]
  def llm_events do
    [
      [:ash_agent, :llm, :request],
      [:ash_agent, :llm, :response],
      [:ash_agent, :llm, :error]
    ]
  end

  @doc """
  Returns all telemetry events emitted by AshAgent.

  This includes agent calls, streams, prompt rendering, and LLM interactions.

  ## Example

      iex> AshAgent.Telemetry.Events.all_events()
      [
        [:ash_agent, :call, :start],
        [:ash_agent, :call, :stop],
        # ... (all events)
      ]
  """
  @spec all_events() :: [telemetry_event()]
  def all_events do
    agent_call_events() ++
      agent_stream_events() ++
      prompt_events() ++
      llm_events()
  end

  @typedoc "A telemetry event name as a list of atoms"
  @type telemetry_event :: [:ash_agent, ...]
end
