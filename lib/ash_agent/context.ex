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

  @doc """
  Keeps only the last N iterations in the context.

  Useful for sliding window compaction where older iterations are discarded.

  ## Examples

      iex> context = %AshAgent.Context{iterations: [%{number: 1}, %{number: 2}, %{number: 3}, %{number: 4}, %{number: 5}], current_iteration: 5}
      iex> compacted = AshAgent.Context.keep_last_iterations(context, 2)
      iex> length(compacted.iterations)
      2
      iex> Enum.map(compacted.iterations, & &1.number)
      [4, 5]
  """
  def keep_last_iterations(context, count) when is_integer(count) and count > 0 do
    recent_iterations = Enum.take(context.iterations, -count)
    %{context | iterations: recent_iterations}
  end

  @doc """
  Removes iterations older than the specified duration (in seconds).

  ## Examples

      iex> old_time = DateTime.add(DateTime.utc_now(), -7200, :second)
      iex> context = %AshAgent.Context{
      ...>   iterations: [
      ...>     %{number: 1, started_at: old_time, metadata: %{}},
      ...>     %{number: 2, started_at: DateTime.utc_now(), metadata: %{}}
      ...>   ],
      ...>   current_iteration: 2
      ...> }
      iex> recent = AshAgent.Context.remove_old_iterations(context, 3600)
      iex> length(recent.iterations)
      1
  """
  def remove_old_iterations(context, max_age_seconds)
      when is_integer(max_age_seconds) and max_age_seconds >= 0 do
    cutoff = DateTime.add(DateTime.utc_now(), -max_age_seconds, :second)

    recent_iterations =
      Enum.filter(context.iterations, fn iteration ->
        case Map.get(iteration, :started_at) do
          nil -> true
          started_at -> DateTime.compare(started_at, cutoff) != :lt
        end
      end)

    %{context | iterations: recent_iterations}
  end

  @doc """
  Returns the number of iterations in the context.

  ## Examples

      iex> context = %AshAgent.Context{iterations: [%{number: 1}, %{number: 2}, %{number: 3}], current_iteration: 3}
      iex> AshAgent.Context.count_iterations(context)
      3
  """
  def count_iterations(context), do: length(context.iterations)

  @doc """
  Gets a slice of iterations by index range.

  ## Examples

      iex> context = %AshAgent.Context{iterations: [%{n: 1}, %{n: 2}, %{n: 3}, %{n: 4}, %{n: 5}], current_iteration: 5}
      iex> sliced = AshAgent.Context.get_iteration_range(context, 1, 3)
      iex> length(sliced.iterations)
      3
      iex> Enum.map(sliced.iterations, & &1.n)
      [2, 3, 4]
  """
  def get_iteration_range(context, start_idx, end_idx)
      when is_integer(start_idx) and is_integer(end_idx) and start_idx >= 0 and
             end_idx >= start_idx do
    count = end_idx - start_idx + 1

    sliced_iterations =
      context.iterations
      |> Enum.drop(start_idx)
      |> Enum.take(count)

    %{context | iterations: sliced_iterations}
  end

  @doc """
  Marks an iteration as summarized and stores the summary.

  ## Examples

      iex> iteration = %{number: 1, messages: [], metadata: %{}}
      iex> summarized = AshAgent.Context.mark_as_summarized(iteration, "User asked about weather")
      iex> summarized.metadata.summarized
      true
      iex> summarized.metadata.summary
      "User asked about weather"
  """
  def mark_as_summarized(iteration, summary) when is_map(iteration) and is_binary(summary) do
    updated_metadata =
      Map.get(iteration, :metadata, %{})
      |> Map.put(:summarized, true)
      |> Map.put(:summary, summary)
      |> Map.put(:summarized_at, DateTime.utc_now())

    Map.put(iteration, :metadata, updated_metadata)
  end

  @doc """
  Checks if an iteration has been summarized.

  ## Examples

      iex> iteration = %{metadata: %{summarized: true}}
      iex> AshAgent.Context.is_summarized?(iteration)
      true

      iex> iteration = %{metadata: %{}}
      iex> AshAgent.Context.is_summarized?(iteration)
      false
  """
  def is_summarized?(iteration) when is_map(iteration) do
    get_in(iteration, [:metadata, :summarized]) == true
  end

  @doc """
  Gets the summary from a summarized iteration.

  Returns nil if iteration is not summarized.

  ## Examples

      iex> iteration = %{metadata: %{summarized: true, summary: "Weather query"}}
      iex> AshAgent.Context.get_summary(iteration)
      "Weather query"

      iex> iteration = %{metadata: %{}}
      iex> AshAgent.Context.get_summary(iteration)
      nil
  """
  def get_summary(iteration) when is_map(iteration) do
    get_in(iteration, [:metadata, :summary])
  end

  @doc """
  Updates iteration metadata with custom key-value pairs.

  ## Examples

      iex> iteration = %{metadata: %{}}
      iex> updated = AshAgent.Context.update_iteration_metadata(iteration, :custom_key, "value")
      iex> updated.metadata.custom_key
      "value"
  """
  def update_iteration_metadata(iteration, key, value)
      when is_map(iteration) and is_atom(key) do
    updated_metadata =
      Map.get(iteration, :metadata, %{})
      |> Map.put(key, value)

    Map.put(iteration, :metadata, updated_metadata)
  end

  @doc """
  Checks if the context exceeds the specified token budget.

  This is a convenience function for Progressive Disclosure hooks.
  Uses `estimate_token_count/1` internally for fast local checking.

  **Note:** This uses token estimation and may be inaccurate. For precise
  tracking, use the provider's actual token counting.

  ## Examples

      iex> small_context = %AshAgent.Context{iterations: []}
      iex> AshAgent.Context.exceeds_token_budget?(small_context, 100_000)
      false
  """
  def exceeds_token_budget?(context, budget)
      when is_integer(budget) and budget > 0 do
    estimate_token_count(context) > budget
  end

  @doc """
  Estimates the token count for the context using a rough heuristic.

  **WARNING:** This is an APPROXIMATION. Assumes ~4 characters per token.
  For accurate counts, use the provider's actual token counting.

  Useful for quick budget checks in hooks without calling external services.

  ## Examples

      iex> context = %AshAgent.Context{iterations: []}
      iex> estimate = AshAgent.Context.estimate_token_count(context)
      iex> is_integer(estimate)
      true
      iex> estimate >= 0
      true

      iex> context = %AshAgent.Context{iterations: [
      ...>   %{messages: [%{role: :user, content: "Hello"}]}
      ...> ]}
      iex> estimate = AshAgent.Context.estimate_token_count(context)
      iex> estimate > 0
      true
  """
  def estimate_token_count(context) do
    messages = to_messages(context)

    Enum.reduce(messages, 0, fn message, acc ->
      content = Map.get(message, "content", "")

      content_tokens = div(String.length(content), 4)

      message_overhead = 10

      acc + content_tokens + message_overhead
    end)
  end

  @doc """
  Calculates remaining tokens before hitting budget.

  Returns 0 if already over budget.

  ## Examples

      iex> context = %AshAgent.Context{iterations: []}
      iex> AshAgent.Context.tokens_remaining(context, 50_000)
      50_000
  """
  def tokens_remaining(context, budget)
      when is_integer(budget) and budget > 0 do
    max(0, budget - estimate_token_count(context))
  end

  @doc """
  Calculates budget utilization as a percentage.

  Returns value between 0.0 and 1.0 (or > 1.0 if over budget).

  ## Examples

      iex> context = %AshAgent.Context{iterations: []}
      iex> utilization = AshAgent.Context.budget_utilization(context, 100_000)
      iex> utilization >= 0.0 and utilization < 0.1
      true
  """
  def budget_utilization(context, budget)
      when is_integer(budget) and budget > 0 do
    estimate_token_count(context) / budget
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
