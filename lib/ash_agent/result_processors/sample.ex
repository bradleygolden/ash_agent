defmodule AshAgent.ResultProcessors.Sample do
  @moduledoc """
  Samples items from list-based tool results.

  Takes the first N items from lists while preserving order.
  Adds metadata about total count.

  ## Options

  - `:sample_size` - Number of items to keep (default: 5)
  - `:strategy` - Sampling strategy: `:first` (default), `:random`, `:distributed`

  ## Examples

      # Sample first 5 items from a large list
      iex> alias AshAgent.ResultProcessors.Sample
      iex> results = [{"query", {:ok, Enum.to_list(1..100)}}]
      iex> sampled = Sample.process(results, sample_size: 5)
      iex> [{"query", {:ok, result}}] = sampled
      iex> result.items
      [1, 2, 3, 4, 5]
      iex> result.total_count
      100

      # Non-list data passes through unchanged
      iex> alias AshAgent.ResultProcessors.Sample
      iex> results = [{"tool", {:ok, "not a list"}}]
      iex> sampled = Sample.process(results)
      iex> [{"tool", {:ok, "not a list"}}] = sampled
      true

      # Error results are preserved
      iex> alias AshAgent.ResultProcessors.Sample
      iex> results = [{"tool", {:error, "oops"}}]
      iex> sampled = Sample.process(results)
      iex> [{"tool", {:error, "oops"}}] = sampled
      true
  """

  @behaviour AshAgent.ResultProcessor

  @default_sample_size 5

  @impl true
  def process(results, opts \\ []) when is_list(results) do
    sample_size = Keyword.get(opts, :sample_size, @default_sample_size)
    strategy = Keyword.get(opts, :strategy, :first)

    unless is_integer(sample_size) and sample_size > 0 do
      raise ArgumentError, "sample_size must be a positive integer, got: #{inspect(sample_size)}"
    end

    unless strategy in [:first, :random, :distributed] do
      raise ArgumentError,
            "strategy must be one of [:first, :random, :distributed], got: #{inspect(strategy)}"
    end

    Enum.map(results, fn result_entry ->
      sample_result(result_entry, sample_size, strategy)
    end)
  end

  defp sample_result({name, {:ok, data}}, sample_size, strategy) do
    sampled_data = sample_data(data, sample_size, strategy)
    {name, {:ok, sampled_data}}
  end

  defp sample_result({_name, {:error, _reason}} = error_result, _sample_size, _strategy) do
    error_result
  end

  defp sample_data(data, sample_size, strategy) when is_list(data) do
    sample_list(data, sample_size, strategy)
  end

  defp sample_data(data, _sample_size, _strategy) do
    data
  end

  defp sample_list(list, sample_size, :first) do
    total_count = length(list)

    if total_count <= sample_size do
      list
    else
      items = Enum.take(list, sample_size)

      %{
        items: items,
        total_count: total_count,
        sampled: true,
        strategy: :first
      }
    end
  end

  defp sample_list(list, sample_size, :random) do
    total_count = length(list)

    if total_count <= sample_size do
      list
    else
      items = Enum.take_random(list, sample_size)

      %{
        items: items,
        total_count: total_count,
        sampled: true,
        strategy: :random
      }
    end
  end

  defp sample_list(list, sample_size, :distributed) do
    total_count = length(list)

    if total_count <= sample_size do
      list
    else
      step = div(total_count, sample_size)

      items =
        0..(sample_size - 1)
        |> Enum.map(fn i -> Enum.at(list, i * step) end)

      %{
        items: items,
        total_count: total_count,
        sampled: true,
        strategy: :distributed
      }
    end
  end
end
