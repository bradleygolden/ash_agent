defmodule AshAgent.ResultProcessors.Summarize do
  @moduledoc """
  Summarizes tool results using rule-based heuristics.

  Automatically detects data type and applies appropriate strategy:
  - Lists: count + sample items
  - Maps: keys + sample values
  - Binaries (text): length + excerpt
  - Nested structures: recursive summarization

  ## Options

  - `:strategy` - Summarization strategy: `:auto` (default), `:list`, `:map`, `:text`
  - `:sample_size` - Number of items to sample (default: 3)
  - `:max_summary_size` - Maximum size of summary output (default: 500)

  ## Examples

      iex> alias AshAgent.ResultProcessors.Summarize
      iex> results = [{"query", {:ok, Enum.to_list(1..100)}}]
      iex> summarized = Summarize.process(results, sample_size: 3)
      iex> [{"query", {:ok, summary}}] = summarized
      iex> summary.type
      "list"
      iex> summary.count
      100
      iex> length(summary.sample)
      3
  """

  @behaviour AshAgent.ResultProcessor

  @default_sample_size 3
  @default_max_summary_size 500
  @max_recursion_depth 3

  @impl true
  def process(results, opts \\ []) when is_list(results) do
    sample_size = Keyword.get(opts, :sample_size, @default_sample_size)
    max_summary_size = Keyword.get(opts, :max_summary_size, @default_max_summary_size)
    strategy = Keyword.get(opts, :strategy, :auto)

    unless is_integer(sample_size) and sample_size > 0 do
      raise ArgumentError,
            "sample_size must be a positive integer, got: #{inspect(sample_size)}"
    end

    unless is_integer(max_summary_size) and max_summary_size > 0 do
      raise ArgumentError,
            "max_summary_size must be a positive integer, got: #{inspect(max_summary_size)}"
    end

    Enum.map(results, fn result_entry ->
      summarize_result(result_entry, strategy, sample_size, max_summary_size)
    end)
  end

  defp summarize_result({name, {:ok, data}}, strategy, sample_size, max_summary_size) do
    summary = summarize_data(data, strategy, sample_size, max_summary_size, 0)
    {name, {:ok, summary}}
  end

  defp summarize_result(
         {_name, {:error, _reason}} = error_result,
         _strategy,
         _sample_size,
         _max_summary_size
       ) do
    error_result
  end

  defp summarize_data(data, :auto, sample_size, max_summary_size, depth) do
    cond do
      is_list(data) ->
        summarize_list(data, sample_size, max_summary_size, depth)

      is_map(data) and not is_struct(data) ->
        summarize_map(data, sample_size, max_summary_size, depth)

      is_binary(data) ->
        summarize_text(data, max_summary_size)

      is_struct(data) ->
        summarize_struct(data, sample_size, max_summary_size, depth)

      true ->
        summarize_other(data)
    end
  end

  defp summarize_data(data, :list, sample_size, max_summary_size, depth) when is_list(data) do
    summarize_list(data, sample_size, max_summary_size, depth)
  end

  defp summarize_data(data, :map, sample_size, max_summary_size, depth) when is_map(data) do
    summarize_map(data, sample_size, max_summary_size, depth)
  end

  defp summarize_data(data, :text, _sample_size, max_summary_size, _depth) when is_binary(data) do
    summarize_text(data, max_summary_size)
  end

  defp summarize_data(data, _strategy, _sample_size, _max_summary_size, _depth) do
    %{
      type: "other",
      summary: "Data of type: #{inspect(data.__struct__ || :unknown)}"
    }
  end

  defp summarize_list(list, sample_size, max_summary_size, depth) do
    count = length(list)
    sample = Enum.take(list, sample_size)

    summary_text = "List with #{count} items"
    sample_data = summarize_list_items(sample, sample_size, max_summary_size, depth)

    %{
      type: "list",
      count: count,
      sample: sample_data,
      summary: summary_text
    }
    |> limit_summary_size(max_summary_size)
  end

  defp summarize_list_items(sample, sample_size, max_summary_size, depth) do
    if depth < @max_recursion_depth do
      Enum.map(sample, fn item ->
        summarize_list_item(item, sample_size, max_summary_size, depth)
      end)
    else
      sample
    end
  end

  defp summarize_list_item(item, sample_size, max_summary_size, depth) do
    if is_list(item) or is_map(item) or is_struct(item) do
      summarize_data(item, :auto, sample_size, max_summary_size, depth + 1)
    else
      item
    end
  end

  defp summarize_map(map, sample_size, max_summary_size, depth) do
    keys = Map.keys(map)
    key_count = length(keys)
    sample_keys = Enum.take(keys, sample_size)

    sample_values = summarize_map_values(map, sample_keys, sample_size, max_summary_size, depth)
    summary_text = "Map with #{key_count} keys"

    %{
      type: "map",
      count: key_count,
      keys: sample_keys,
      sample: sample_values,
      summary: summary_text
    }
    |> limit_summary_size(max_summary_size)
  end

  defp summarize_map_values(map, sample_keys, sample_size, max_summary_size, depth) do
    if depth < @max_recursion_depth do
      Map.new(sample_keys, fn key ->
        {key, summarize_map_value(Map.get(map, key), sample_size, max_summary_size, depth)}
      end)
    else
      Map.take(map, sample_keys)
    end
  end

  defp summarize_map_value(value, sample_size, max_summary_size, depth) do
    if is_list(value) or is_map(value) or is_struct(value) do
      summarize_data(value, :auto, sample_size, max_summary_size, depth + 1)
    else
      value
    end
  end

  defp summarize_text(text, max_summary_size) do
    text_length = String.length(text)
    excerpt_length = min(100, max_summary_size - 50)
    excerpt = String.slice(text, 0, excerpt_length)

    summary_text = "Text with #{text_length} characters"

    %{
      type: "text",
      length: text_length,
      excerpt: excerpt,
      summary: summary_text
    }
    |> limit_summary_size(max_summary_size)
  end

  defp summarize_struct(struct, sample_size, max_summary_size, depth) do
    struct_name = inspect(struct.__struct__)

    if depth >= @max_recursion_depth do
      %{
        type: "struct",
        struct_name: struct_name,
        summary: "#{struct_name} (max depth reached)"
      }
    else
      map_data = Map.from_struct(struct)
      map_summary = summarize_map(map_data, sample_size, max_summary_size, depth)

      %{
        type: "struct",
        struct_name: struct_name,
        fields: map_summary,
        summary: "#{struct_name} with #{map_size(map_data)} fields"
      }
      |> limit_summary_size(max_summary_size)
    end
  end

  defp summarize_other(data) do
    type =
      cond do
        is_atom(data) -> "atom"
        is_number(data) -> "number"
        is_function(data) -> "function"
        is_pid(data) -> "pid"
        is_reference(data) -> "reference"
        true -> "unknown"
      end

    %{
      type: "other",
      data_type: type,
      summary: "#{String.capitalize(type)}: #{inspect(data)}"
    }
  end

  defp limit_summary_size(summary, max_size) do
    summary_size = :erlang.external_size(summary)

    if summary_size > max_size do
      summary
      |> Map.delete(:sample)
      |> Map.put(:sample_removed, true)
      |> Map.put(:reason, "Summary exceeded max size (#{summary_size} > #{max_size})")
    else
      summary
    end
  end
end
