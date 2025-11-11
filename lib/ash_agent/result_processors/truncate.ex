defmodule AshAgent.ResultProcessors.Truncate do
  @moduledoc """
  Truncates tool results that exceed a specified size threshold.

  Supports truncation of:
  - Binaries (strings) - truncated by character count (UTF-8 safe)
  - Lists - truncated by item count
  - Maps - truncated by key count

  Error results are preserved unchanged.

  ## Options

  - `:max_size` - Maximum size in bytes/items (default: 1000)
  - `:marker` - Truncation indicator text (default: "... [truncated]")

  ## Examples

      # Truncate a large string
      iex> results = [{"tool", {:ok, String.duplicate("x", 2000)}}]
      iex> truncated = AshAgent.ResultProcessors.Truncate.process(results, max_size: 100)
      iex> [{"tool", {:ok, data}}] = truncated
      iex> String.length(data) <= 120
      true

      # Small results pass through unchanged
      iex> results = [{"tool", {:ok, "small"}}]
      iex> [{"tool", {:ok, "small"}}] = AshAgent.ResultProcessors.Truncate.process(results, max_size: 100)
      [{"tool", {:ok, "small"}}]

      # Error results are preserved
      iex> results = [{"tool", {:error, "oops"}}]
      iex> [{"tool", {:error, "oops"}}] = AshAgent.ResultProcessors.Truncate.process(results)
      [{"tool", {:error, "oops"}}]

  """

  @behaviour AshAgent.ResultProcessor

  alias AshAgent.ResultProcessors

  @default_max_size 1_000
  @default_marker "... [truncated]"

  @impl true
  def process(results, opts \\ []) when is_list(results) do
    max_size = Keyword.get(opts, :max_size, @default_max_size)
    marker = Keyword.get(opts, :marker, @default_marker)

    unless is_integer(max_size) and max_size > 0 do
      raise ArgumentError, "max_size must be a positive integer, got: #{inspect(max_size)}"
    end

    Enum.map(results, fn result_entry ->
      truncate_result(result_entry, max_size, marker)
    end)
  end

  defp truncate_result({name, {:ok, data}} = entry, max_size, marker) do
    if ResultProcessors.large?(data, max_size) do
      truncated_data = truncate_data(data, max_size, marker)
      {name, {:ok, truncated_data}}
    else
      entry
    end
  end

  defp truncate_result({_name, {:error, _reason}} = entry, _max_size, _marker) do
    entry
  end

  defp truncate_data(data, max_size, marker) when is_binary(data) do
    if String.length(data) > max_size do
      String.slice(data, 0, max_size) <> marker
    else
      data
    end
  end

  defp truncate_data(data, max_size, marker) when is_list(data) do
    if length(data) > max_size do
      Enum.take(data, max_size) ++ [marker]
    else
      data
    end
  end

  defp truncate_data(data, max_size, marker) when is_map(data) do
    keys = Map.keys(data)
    key_count = length(keys)

    if key_count > max_size do
      kept_keys = Enum.take(keys, max_size)
      truncated_map = Map.take(data, kept_keys)

      Map.put(truncated_map, :__truncated__, marker)
    else
      data
    end
  end

  defp truncate_data(data, _max_size, _marker) do
    data
  end
end
