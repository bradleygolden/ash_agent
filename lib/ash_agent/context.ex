defmodule AshAgent.Context do
  @moduledoc """
  Conversation context for AshAgent execution.

  Context wraps a list of messages and tracks metadata for agent execution.
  It's the primary data structure passed to agent actions.

  ## Creating Context

  Context is typically created via the generated `context/1` function on agent modules:

      context =
        [
          ChatAgent.instruction(company_name: "Acme"),
          ChatAgent.user(message: "Hello!")
        ]
        |> ChatAgent.context()

  ## Multi-turn Conversations

  After an agent call, the result includes an updated context with the assistant's
  response. Use this for multi-turn conversations:

      {:ok, result} = ChatAgent.call(context)

      # Continue the conversation
      new_context =
        [
          result.context,
          ChatAgent.user(message: "Follow up question")
        ]
        |> ChatAgent.context()

      {:ok, result2} = ChatAgent.call(new_context)

  ## Structure

  The context contains:
  - `:messages` - List of `AshAgent.Message` structs
  - `:metadata` - Optional metadata map for tracking state
  - `:input` - Original input arguments (used by BAML provider)
  """

  alias AshAgent.Message

  defstruct messages: [], metadata: %{}, input: nil

  @type t :: %__MODULE__{
          messages: [Message.t()],
          metadata: map(),
          input: map() | nil
        }

  @doc """
  Creates a new context from a list of messages.

  Accepts a list that can contain:
  - `AshAgent.Message` structs
  - Other `AshAgent.Context` structs (for multi-turn)

  Messages are flattened and validated for well-formedness.

  ## Examples

      context = AshAgent.Context.new([
        AshAgent.Message.system("You are helpful"),
        AshAgent.Message.user(%{message: "Hello"})
      ])

  """
  def new(messages, opts \\ []) when is_list(messages) do
    flattened = flatten_messages(messages)
    metadata = Keyword.get(opts, :metadata, %{})
    input = Keyword.get(opts, :input)

    %__MODULE__{
      messages: flattened,
      metadata: metadata,
      input: input
    }
  end

  @doc """
  Returns the messages formatted for LLM provider consumption.

  Extracts the system prompt (if present) and returns it separately
  along with the conversation messages.
  """
  def to_provider_format(%__MODULE__{messages: messages}) do
    {system_messages, other_messages} =
      Enum.split_with(messages, fn msg -> msg.role == :system end)

    system_prompt =
      case system_messages do
        [] -> nil
        [msg | _] -> msg.content
      end

    conversation =
      Enum.map(other_messages, &Message.to_provider_format/1)

    {system_prompt, conversation}
  end

  @doc """
  Returns just the messages list.
  """
  def messages(%__MODULE__{messages: messages}), do: messages

  @doc """
  Adds an assistant message to the context.
  """
  def add_assistant_message(%__MODULE__{} = context, content) do
    message = Message.assistant(content)
    %{context | messages: context.messages ++ [message]}
  end

  @doc """
  Adds a user message to the context.
  """
  def add_user_message(%__MODULE__{} = context, content) do
    message = Message.user(content)
    %{context | messages: context.messages ++ [message]}
  end

  @doc """
  Updates the context metadata.
  """
  def put_metadata(%__MODULE__{} = context, key, value) do
    %{context | metadata: Map.put(context.metadata, key, value)}
  end

  @doc """
  Gets a value from context metadata.
  """
  def get_metadata(%__MODULE__{metadata: metadata}, key, default \\ nil) do
    Map.get(metadata, key, default)
  end

  defp flatten_messages(items) do
    Enum.flat_map(items, fn
      %__MODULE__{messages: msgs} -> msgs
      %Message{} = msg -> [msg]
    end)
  end
end
