defmodule AshAgent.Context do
  @moduledoc """
  A minimal embedded resource that stores conversation history using nested iterations.
  """
  defmodule Domain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      allow_unregistered? true
    end
  end

  use Ash.Resource,
    data_layer: :embedded,
    domain: __MODULE__.Domain

  require Jason

  attributes do
    attribute :iterations, {:array, :map} do
      default []
      allow_nil? false
    end

    attribute :current_iteration, :integer do
      default 0
      allow_nil? false
    end
  end

  actions do
    defaults [:read]

    create :create do
      accept [:iterations, :current_iteration]
    end

    update :update do
      accept [:iterations, :current_iteration]
    end
  end

  code_interface do
    define :create
    define :update
  end

  @doc """
  Creates a new context with initial user message.
  """
  def new(input, opts \\ []) do
    messages = []

    messages =
      if system_prompt = Keyword.get(opts, :system_prompt) do
        [%{role: :system, content: system_prompt} | messages]
      else
        messages
      end

    messages = messages ++ [user_message(input)]

    iteration = %{
      number: 1,
      messages: messages,
      tool_calls: [],
      started_at: DateTime.utc_now(),
      completed_at: nil,
      metadata: %{}
    }

    create!(%{iterations: [iteration], current_iteration: 1})
  end

  @doc """
  Adds an assistant message to the current iteration.
  """
  def add_assistant_message(context, content, tool_calls \\ []) do
    message = %{
      role: :assistant,
      content: content,
      tool_calls: if(tool_calls == [] or is_nil(tool_calls), do: nil, else: tool_calls)
    }

    current_iter = get_current_iteration(context)
    updated_iter = %{current_iter | messages: current_iter.messages ++ [message]}

    iterations =
      List.replace_at(context.iterations, context.current_iteration - 1, updated_iter)

    update!(context, %{iterations: iterations})
  end

  @doc """
  Adds tool results to the conversation.
  """
  def add_tool_results(context, results) do
    tool_result_messages =
      Enum.map(results, fn {tool_call_id, result} ->
        content = format_tool_result(result)

        %{
          role: :user,
          content: [%{type: :tool_result, tool_use_id: tool_call_id, content: content}]
        }
      end)

    current_iter = get_current_iteration(context)
    updated_iter = %{current_iter | messages: current_iter.messages ++ tool_result_messages}

    iterations =
      List.replace_at(context.iterations, context.current_iteration - 1, updated_iter)

    update!(context, %{iterations: iterations})
  end

  @doc """
  Extracts tool calls from the last assistant message in current iteration.
  """
  def extract_tool_calls(context) do
    current_iter = get_current_iteration(context)

    case List.last(current_iter.messages) do
      %{role: :assistant, tool_calls: tool_calls} when is_list(tool_calls) ->
        tool_calls

      _ ->
        []
    end
  end

  @doc """
  Converts all iteration messages to provider-specific message format.
  """
  def to_messages(context) do
    messages =
      Enum.flat_map(context.iterations, fn iteration ->
        iteration.messages
      end)

    Enum.map(messages, &format_message/1)
  end

  @doc """
  Checks if the context has exceeded max iterations.
  """
  def exceeded_max_iterations?(context, max_iterations) do
    context.current_iteration >= max_iterations
  end

  @doc """
  Gets a specific iteration by number.
  """
  def get_iteration(context, number) do
    Enum.find(context.iterations, fn iter -> iter.number == number end)
  end

  @doc """
  Adds token usage to the current iteration's metadata.
  """
  def add_token_usage(context, usage) when is_map(usage) do
    current_iter = get_current_iteration(context)
    current_metadata = current_iter.metadata || %{}

    cumulative = get_cumulative_tokens(context)

    input_tokens = Map.get(usage, :input_tokens, 0) + Map.get(usage, "input_tokens", 0)
    output_tokens = Map.get(usage, :output_tokens, 0) + Map.get(usage, "output_tokens", 0)

    total_tokens =
      Map.get(usage, :total_tokens) || Map.get(usage, "total_tokens") ||
        input_tokens + output_tokens

    new_cumulative = %{
      input_tokens: Map.get(cumulative, :input_tokens, 0) + input_tokens,
      output_tokens: Map.get(cumulative, :output_tokens, 0) + output_tokens,
      total_tokens: Map.get(cumulative, :total_tokens, 0) + total_tokens
    }

    updated_metadata =
      current_metadata
      |> Map.put(:current_usage, usage)
      |> Map.put(:cumulative_tokens, new_cumulative)

    updated_iter = %{current_iter | metadata: updated_metadata}
    iterations = List.replace_at(context.iterations, context.current_iteration - 1, updated_iter)

    update!(context, %{iterations: iterations})
  end

  @doc """
  Gets cumulative token usage across all iterations.
  """
  def get_cumulative_tokens(context) do
    current_iter = get_current_iteration(context)
    current_metadata = current_iter.metadata || %{}

    Map.get(current_metadata, :cumulative_tokens, %{
      input_tokens: 0,
      output_tokens: 0,
      total_tokens: 0
    })
  end

  defp get_current_iteration(context) do
    Enum.at(context.iterations, context.current_iteration - 1)
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

  defp format_message(%{role: :system, content: content}) do
    %{role: "system", content: content}
  end

  defp format_message(%{role: role, content: content, tool_calls: nil})
       when role in [:user, :assistant, :system] do
    %{role: to_string(role), content: content}
  end

  defp format_message(%{role: :assistant, content: content, tool_calls: tool_calls}) do
    %{
      role: "assistant",
      content: content,
      tool_calls: Enum.map(tool_calls, &format_tool_call/1)
    }
  end

  defp format_message(%{role: :user, content: [%{type: :tool_result} | _] = parts}) do
    %{role: "user", content: parts}
  end

  defp format_message(%{role: role, content: content})
       when role in [:user, :assistant, :system] do
    %{role: to_string(role), content: content}
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
