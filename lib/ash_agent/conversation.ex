defmodule AshAgent.Conversation do
  @moduledoc """
  Manages conversation state for multi-turn agent interactions with tool calling.

  Tracks messages, tool calls, and results across multiple iterations.
  """

  require Jason

  defstruct [
    :agent,
    :domain,
    :actor,
    :tenant,
    messages: [],
    tool_calls: [],
    iteration: 0,
    max_iterations: 10
  ]

  @type t :: %__MODULE__{
          agent: module(),
          domain: module() | nil,
          actor: term() | nil,
          tenant: term() | nil,
          messages: [message()],
          tool_calls: [tool_call()],
          iteration: non_neg_integer(),
          max_iterations: pos_integer()
        }

  @type message :: %{
          role: :user | :assistant | :system,
          content: String.t() | [content_part()],
          tool_calls: [tool_call()] | nil,
          tool_call_id: String.t() | nil
        }

  @type content_part :: %{
          type: :text | :tool_use | :tool_result,
          text: String.t() | nil,
          id: String.t() | nil,
          name: String.t() | nil,
          input: map() | nil,
          tool_use_id: String.t() | nil,
          content: String.t() | nil
        }

  @type tool_call :: %{
          id: String.t(),
          name: String.t(),
          arguments: map()
        }

  @doc """
  Creates a new conversation with initial user message.
  """
  @spec new(module(), map(), keyword()) :: t()
  def new(agent, input, opts \\ []) do
    %__MODULE__{
      agent: agent,
      domain: Keyword.get(opts, :domain),
      actor: Keyword.get(opts, :actor),
      tenant: Keyword.get(opts, :tenant),
      max_iterations: Keyword.get(opts, :max_iterations, 10),
      messages: [user_message(input)]
    }
  end

  @doc """
  Adds an assistant message to the conversation.
  """
  @spec add_assistant_message(t(), String.t() | [content_part()], [tool_call()]) :: t()
  def add_assistant_message(conversation, content, tool_calls \\ []) do
    message = %{
      role: :assistant,
      content: content,
      tool_calls: if(tool_calls == [], do: nil, else: tool_calls)
    }

    %{conversation | messages: conversation.messages ++ [message], iteration: conversation.iteration + 1}
  end

  @doc """
  Adds tool results to the conversation.
  """
  @spec add_tool_results(t(), [{String.t(), {:ok, term()} | {:error, term()}}]) :: t()
  def add_tool_results(conversation, results) do
    tool_result_messages =
      Enum.map(results, fn {tool_call_id, result} ->
        content = format_tool_result(result)
        %{role: :user, content: [%{type: :tool_result, tool_use_id: tool_call_id, content: content}]}
      end)

    %{conversation | messages: conversation.messages ++ tool_result_messages}
  end

  @doc """
  Checks if the conversation has exceeded max iterations.
  """
  @spec exceeded_max_iterations?(t()) :: boolean()
  def exceeded_max_iterations?(%{iteration: iteration, max_iterations: max}) do
    iteration >= max
  end

  @doc """
  Extracts tool calls from the last assistant message.
  """
  @spec extract_tool_calls(t()) :: [tool_call()]
  def extract_tool_calls(%{messages: messages}) do
    case List.last(messages) do
      %{role: :assistant, tool_calls: tool_calls} when is_list(tool_calls) ->
        tool_calls

      _ ->
        []
    end
  end

  @doc """
  Converts conversation to provider-specific message format.
  """
  @spec to_messages(t()) :: [map()]
  def to_messages(%{messages: messages}) do
    Enum.map(messages, &format_message/1)
  end

  defp user_message(input) when is_map(input) do
    content = format_user_input(input)
    %{role: :user, content: content}
  end

  defp user_message(input) when is_binary(input) do
    %{role: :user, content: input}
  end

  defp format_user_input(input) do
    case Map.get(input, :message) do
      nil -> Jason.encode!(input)
      message -> message
    end
  end

  defp format_message(%{role: role, content: content, tool_calls: nil}) do
    %{role: role, content: content}
  end

  defp format_message(%{role: :assistant, content: content, tool_calls: tool_calls}) do
    %{
      role: :assistant,
      content: content,
      tool_calls: Enum.map(tool_calls, &format_tool_call/1)
    }
  end

  defp format_message(%{role: :user, content: [%{type: :tool_result} | _] = parts}) do
    %{role: :user, content: parts}
  end

  defp format_message(%{role: role, content: content}) do
    %{role: role, content: content}
  end

  defp format_tool_call(%{id: id, name: name, arguments: args}) do
    %{
      id: id,
      type: "function",
      function: %{
        name: name,
        arguments: Jason.encode!(args)
      }
    }
  end

  defp format_tool_result({:ok, result}) when is_map(result) do
    Jason.encode!(result)
  end

  defp format_tool_result({:ok, result}) do
    Jason.encode!(%{result: result})
  end

  defp format_tool_result({:error, reason}) do
    error_msg = if is_binary(reason), do: reason, else: inspect(reason)
    Jason.encode!(%{error: error_msg})
  end
end

