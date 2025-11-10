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
      iex> truncated = AshAgent.ResultProcessors.Truncate.process(results, max_size: 100)
      iex> [{"tool", {:ok, "small"}}] = truncated
      true

      # Error results are preserved
      iex> results = [{"tool", {:error, "oops"}}]
      iex> truncated = AshAgent.ResultProcessors.Truncate.process(results)
      iex> [{"tool", {:error, "oops"}}] = truncated
      true

  """

  @behaviour AshAgent.ResultProcessor

  alias AshAgent.ResultProcessors

  @default_max_size 1_000
  @default_marker "... [truncated]"

  @impl true
  def process(results, opts \\ []) when is_list(results) do
    max_size = Keyword.get(opts, :max_size, @default_max_size)
    marker = Keyword.get(opts, :marker, @default_marker)

    # Validate max_size
    unless is_integer(max_size) and max_size > 0 do
      raise ArgumentError, "max_size must be a positive integer, got: #{inspect(max_size)}"
    end

    Enum.map(results, fn result_entry ->
      truncate_result(result_entry, max_size, marker)
    end)
  end

  # Truncate a single result entry
  defp truncate_result({name, {:ok, data}} = entry, max_size, marker) do
    if ResultProcessors.large?(data, max_size) do
      truncated_data = truncate_data(data, max_size, marker)
      {name, {:ok, truncated_data}}
    else
      # Data is small enough, pass through unchanged
      entry
    end
  end

  # Preserve error results unchanged
  defp truncate_result({_name, {:error, _reason}} = entry, _max_size, _marker) do
    entry
  end

  # Truncate binary data (UTF-8 safe!)
  defp truncate_data(data, max_size, marker) when is_binary(data) do
    # Use String.slice for UTF-8 safety, not binary_part
    if String.length(data) > max_size do
      String.slice(data, 0, max_size) <> marker
    else
      data
    end
  end

  # Truncate list data
  defp truncate_data(data, max_size, marker) when is_list(data) do
    if length(data) > max_size do
      Enum.take(data, max_size) ++ [marker]
    else
      data
    end
  end

  # Truncate map data
  defp truncate_data(data, max_size, marker) when is_map(data) do
    keys = Map.keys(data)
    key_count = length(keys)

    if key_count > max_size do
      # Take first max_size keys
      kept_keys = Enum.take(keys, max_size)
      truncated_map = Map.take(data, kept_keys)

      # Add truncation marker
      Map.put(truncated_map, :__truncated__, marker)
    else
      data
    end
  end

  # Pass through other types unchanged
  defp truncate_data(data, _max_size, _marker) do
    data
  end
end
