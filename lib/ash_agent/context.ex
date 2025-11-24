defmodule AshAgent.Context do
  @moduledoc """
  Base context implementation for AshAgent runtime.

  This module provides the standard context structure for tracking conversation state,
  iterations, messages, and token usage across agent calls.

  Extension packages can provide their own context implementations by registering
  them with `AshAgent.RuntimeRegistry.register_context_module/1`. The context module
  should implement the same function signatures as this module (duck typing).

  ## Required Functions

  Context modules should implement:
  - `new(input, opts)` - Create new context
  - `to_messages(context)` - Convert to message format
  - `add_assistant_message(context, content, tool_calls)` - Add assistant message
  - `add_llm_call_timing(context)` - Track timing
  - `add_token_usage(context, usage)` - Track token usage
  - `get_cumulative_tokens(context)` - Get cumulative tokens
  - `exceeded_max_iterations?(context, max)` - Check iteration limit
  - `persist(context, attrs)` - Update context state

  ## Example

      # Base context for agents without tools
      ctx = AshAgent.Context.new(input, system_prompt: prompt)
      messages = AshAgent.Context.to_messages(ctx)
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
  Creates a new context with the given input.

  ## Options

  - `:system_prompt` - Optional system prompt to prepend to messages

  ## Examples

      iex> ctx = AshAgent.Context.new(%{question: "What is Elixir?"})
      iex> ctx.current_iteration
      1
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

  ## Parameters

  - `context` - The context to update
  - `content` - The message content
  - `tool_calls` - Optional list of tool calls made by the assistant
  """
  def add_assistant_message(context, content, tool_calls \\ []) do
    message = %{
      role: :assistant,
      content: content,
      tool_calls: if(tool_calls == [] or is_nil(tool_calls), do: nil, else: tool_calls)
    }

    current_iter = get_current_iteration(context)

    updated_iter =
      current_iter
      |> Map.update!(:messages, &(&1 ++ [message]))
      |> Map.update!(:tool_calls, fn existing_calls ->
        if is_list(tool_calls) and length(tool_calls) > 0 do
          existing_calls ++ tool_calls
        else
          existing_calls
        end
      end)

    iterations =
      List.replace_at(context.iterations, context.current_iteration - 1, updated_iter)

    update!(context, %{iterations: iterations})
  end

  @doc """
  Records timing information for the LLM call in the current iteration.
  """
  def add_llm_call_timing(context) do
    current_iter = get_current_iteration(context)
    current_metadata = current_iter.metadata || %{}

    llm_response_time = DateTime.utc_now()
    start_time = current_iter.started_at

    duration_ms =
      if start_time do
        DateTime.diff(llm_response_time, start_time, :millisecond)
      else
        0
      end

    updated_metadata =
      Map.merge(current_metadata, %{
        llm_response_at: llm_response_time,
        llm_duration_ms: duration_ms
      })

    updated_iter = %{current_iter | metadata: updated_metadata}

    iterations =
      List.replace_at(context.iterations, context.current_iteration - 1, updated_iter)

    update!(context, %{iterations: iterations})
  end

  @doc """
  Converts the context to a list of messages suitable for LLM providers.
  """
  def to_messages(context) do
    messages =
      Enum.flat_map(context.iterations, fn iteration ->
        iteration.messages
      end)

    Enum.map(messages, &format_message/1)
  end

  @doc """
  Checks if the context has exceeded the maximum iteration count.
  """
  def exceeded_max_iterations?(context, max_iterations) do
    context.current_iteration >= max_iterations
  end

  def get_iteration(context, number) do
    Enum.find(context.iterations, fn iter -> iter.number == number end)
  end

  @doc """
  Adds token usage information to the current iteration and updates cumulative totals.
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
  Gets the cumulative token usage across all iterations.
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
  Persists updates to the context.
  """
  def persist(context, attrs) do
    context
    |> Ash.Changeset.for_update(:update, attrs)
    |> Ash.update!()
  end

  def keep_last_iterations(context, count) when is_integer(count) and count > 0 do
    recent_iterations = Enum.take(context.iterations, -count)
    %{context | iterations: recent_iterations}
  end

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

  def count_iterations(context), do: length(context.iterations)

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

  def mark_as_summarized(iteration, summary) when is_map(iteration) and is_binary(summary) do
    updated_metadata =
      Map.get(iteration, :metadata, %{})
      |> Map.put(:summarized, true)
      |> Map.put(:summary, summary)
      |> Map.put(:summarized_at, DateTime.utc_now())

    Map.put(iteration, :metadata, updated_metadata)
  end

  def is_summarized?(iteration) when is_map(iteration) do
    get_in(iteration, [:metadata, :summarized]) == true
  end

  def get_summary(iteration) when is_map(iteration) do
    get_in(iteration, [:metadata, :summary])
  end

  def update_iteration_metadata(iteration, key, value)
      when is_map(iteration) and is_atom(key) do
    updated_metadata =
      Map.get(iteration, :metadata, %{})
      |> Map.put(key, value)

    Map.put(iteration, :metadata, updated_metadata)
  end

  def exceeds_token_budget?(context, budget)
      when is_integer(budget) and budget > 0 do
    estimate_token_count(context) > budget
  end

  def estimate_token_count(context) do
    messages = to_messages(context)

    Enum.reduce(messages, 0, fn message, acc ->
      content = Map.get(message, "content", "")

      content_tokens = div(String.length(content), 4)

      message_overhead = 10

      acc + content_tokens + message_overhead
    end)
  end

  def tokens_remaining(context, budget)
      when is_integer(budget) and budget > 0 do
    max(0, budget - estimate_token_count(context))
  end

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
end
