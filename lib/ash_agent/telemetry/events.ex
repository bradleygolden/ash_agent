defmodule AshAgent.Telemetry.Events do
  @moduledoc """
  Defines the telemetry event schema for AshAgent.

  This module provides the canonical list of telemetry events emitted by AshAgent
  and extension packages. These event names are part of the public API contract.

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
  - `[:ash_agent, :stream, :exception]` - Stream raised an exception
  - `[:ash_agent, :stream, :summary]` - Summary metrics after stream completion

  ### Tool Execution Events
  Emitted by tool execution extension packages:
  - `[:ash_agent, :tool_call, :start]` - Tool execution started
  - `[:ash_agent, :tool_call, :complete]` - Tool execution completed successfully
  - `[:ash_agent, :tool_call, :decision]` - Tool execution decision made
  - `[:ash_agent, :tool_call, :retry]` - Tool execution retry attempted
  - `[:ash_agent, :tool_call, :error]` - Tool execution encountered an error
  - `[:ash_agent, :tool_call, :exception]` - Tool execution raised an exception

  ### Iteration Events
  Emitted during multi-turn agent loops:
  - `[:ash_agent, :iteration, :start]` - Agent iteration started
  - `[:ash_agent, :iteration, :stop]` - Agent iteration completed

  ### Token Management Events
  Emitted when token limits are approached or exceeded:
  - `[:ash_agent, :token_limit_warning]` - Token limit warning threshold reached
  - `[:ash_agent, :token_limit_progress]` - Token usage progress update

  ### Hook Events
  Emitted during hook execution:
  - `[:ash_agent, :hook, :start]` - Hook execution started
  - `[:ash_agent, :hook, :stop]` - Hook execution completed
  - `[:ash_agent, :hook, :error]` - Hook execution encountered an error

  ### Progressive Disclosure Events
  Emitted during progressive disclosure strategies:
  - `[:ash_agent, :progressive_disclosure, :process_results]` - Processing results with progressive disclosure
  - `[:ash_agent, :progressive_disclosure, :sliding_window]` - Applying sliding window strategy
  - `[:ash_agent, :progressive_disclosure, :token_based]` - Applying token-based strategy

  ### Prompt Rendering Events
  Emitted during prompt template rendering:
  - `[:ash_agent, :prompt, :rendered]` - Prompt template was rendered

  ### LLM Request Events
  Emitted during LLM provider interactions:
  - `[:ash_agent, :llm, :request]` - LLM request sent
  - `[:ash_agent, :llm, :response]` - LLM response received

  ### Stream Chunk Events
  Emitted during streaming responses:
  - `[:ash_agent, :stream, :chunk]` - Stream chunk received

  ### Annotation Events
  Emitted for custom annotations:
  - `[:ash_agent, :annotation]` - Custom annotation event

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

  ### Tool Call Metadata
  - `:tool_name` - Name of the tool being executed
  - `:tool_module` - Module implementing the tool
  - `:arguments` - Tool invocation arguments

  ### Prompt Rendered Metadata
  - `:prompt` - The rendered prompt string

  ### LLM Request/Response Metadata
  - `:messages` - The message history sent to the LLM
  - `:response` - The LLM response structure
  - `:schema` - JSON schema for structured output (if applicable)

  ## Usage Example

      # Attach a telemetry handler
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
        [:ash_agent, :stream, :exception],
        [:ash_agent, :stream, :summary]
      ]
  """
  @spec agent_stream_events() :: [telemetry_event()]
  def agent_stream_events do
    [
      [:ash_agent, :stream, :start],
      [:ash_agent, :stream, :stop],
      [:ash_agent, :stream, :exception],
      [:ash_agent, :stream, :summary]
    ]
  end

  @doc """
  Returns all tool execution-related events.

  These events are emitted by tool execution extension packages.

  ## Example

      iex> AshAgent.Telemetry.Events.tool_call_events()
      [
        [:ash_agent, :tool_call, :start],
        [:ash_agent, :tool_call, :complete],
        [:ash_agent, :tool_call, :decision],
        [:ash_agent, :tool_call, :retry],
        [:ash_agent, :tool_call, :error],
        [:ash_agent, :tool_call, :exception]
      ]
  """
  @spec tool_call_events() :: [telemetry_event()]
  def tool_call_events do
    [
      [:ash_agent, :tool_call, :start],
      [:ash_agent, :tool_call, :complete],
      [:ash_agent, :tool_call, :decision],
      [:ash_agent, :tool_call, :retry],
      [:ash_agent, :tool_call, :error],
      [:ash_agent, :tool_call, :exception]
    ]
  end

  @doc """
  Returns all iteration-related events.

  These events are emitted during multi-turn agent loops.

  ## Example

      iex> AshAgent.Telemetry.Events.iteration_events()
      [
        [:ash_agent, :iteration, :start],
        [:ash_agent, :iteration, :stop]
      ]
  """
  @spec iteration_events() :: [telemetry_event()]
  def iteration_events do
    [
      [:ash_agent, :iteration, :start],
      [:ash_agent, :iteration, :stop]
    ]
  end

  @doc """
  Returns all token management events.

  ## Example

      iex> AshAgent.Telemetry.Events.token_events()
      [
        [:ash_agent, :token_limit_warning],
        [:ash_agent, :token_limit_progress]
      ]
  """
  @spec token_events() :: [telemetry_event()]
  def token_events do
    [
      [:ash_agent, :token_limit_warning],
      [:ash_agent, :token_limit_progress]
    ]
  end

  @doc """
  Returns all hook execution events.

  ## Example

      iex> AshAgent.Telemetry.Events.hook_events()
      [
        [:ash_agent, :hook, :start],
        [:ash_agent, :hook, :stop],
        [:ash_agent, :hook, :error]
      ]
  """
  @spec hook_events() :: [telemetry_event()]
  def hook_events do
    [
      [:ash_agent, :hook, :start],
      [:ash_agent, :hook, :stop],
      [:ash_agent, :hook, :error]
    ]
  end

  @doc """
  Returns all progressive disclosure events.

  ## Example

      iex> AshAgent.Telemetry.Events.progressive_disclosure_events()
      [
        [:ash_agent, :progressive_disclosure, :process_results],
        [:ash_agent, :progressive_disclosure, :sliding_window],
        [:ash_agent, :progressive_disclosure, :token_based]
      ]
  """
  @spec progressive_disclosure_events() :: [telemetry_event()]
  def progressive_disclosure_events do
    [
      [:ash_agent, :progressive_disclosure, :process_results],
      [:ash_agent, :progressive_disclosure, :sliding_window],
      [:ash_agent, :progressive_disclosure, :token_based]
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
        [:ash_agent, :llm, :response]
      ]
  """
  @spec llm_events() :: [telemetry_event()]
  def llm_events do
    [
      [:ash_agent, :llm, :request],
      [:ash_agent, :llm, :response]
    ]
  end

  @doc """
  Returns all stream chunk events.

  ## Example

      iex> AshAgent.Telemetry.Events.stream_chunk_events()
      [[:ash_agent, :stream, :chunk]]
  """
  @spec stream_chunk_events() :: [telemetry_event()]
  def stream_chunk_events do
    [[:ash_agent, :stream, :chunk]]
  end

  @doc """
  Returns all annotation events.

  ## Example

      iex> AshAgent.Telemetry.Events.annotation_events()
      [[:ash_agent, :annotation]]
  """
  @spec annotation_events() :: [telemetry_event()]
  def annotation_events do
    [[:ash_agent, :annotation]]
  end

  @doc """
  Returns all telemetry events emitted by AshAgent and extension packages.

  This includes agent calls, streams, tool executions, iterations, token management,
  hooks, progressive disclosure, prompt rendering, LLM interactions, stream chunks,
  and annotations.

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
      tool_call_events() ++
      iteration_events() ++
      token_events() ++
      hook_events() ++
      progressive_disclosure_events() ++
      prompt_events() ++
      llm_events() ++
      stream_chunk_events() ++
      annotation_events()
  end

  @typedoc "A telemetry event name as a list of atoms"
  @type telemetry_event :: [:ash_agent, ...]
end
