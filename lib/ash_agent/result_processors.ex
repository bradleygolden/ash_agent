defmodule AshAgent.ResultProcessor do
  @moduledoc """
  Behavior for result processors that transform tool results.

  Result processors follow a common contract:
  - Accept list of `{tool_name, result}` tuples
  - Return list of `{tool_name, transformed_result}` tuples
  - Preserve tuple structure and ordering
  - Preserve error results unchanged
  """

  @type tool_name :: String.t()
  @type tool_result :: {:ok, any()} | {:error, any()}
  @type result_entry :: {tool_name, tool_result}
  @type options :: keyword()

  @callback process([result_entry], options) :: [result_entry]
end

defmodule AshAgent.ResultProcessors do
  @moduledoc """
  Shared utilities for result processors.
  """

  @doc """
  Checks if a result is considered "large" based on estimated size.

  ## Examples

      iex> AshAgent.ResultProcessors.large?("small", 1000)
      false

      iex> large = String.duplicate("x", 2000)
      iex> AshAgent.ResultProcessors.large?(large, 1000)
      true
  """
  def large?(data, threshold) do
    estimate_size(data) > threshold
  end

  @doc """
  Estimates the size of data in bytes/items.

  - Binaries: byte_size
  - Lists: length
  - Maps: map_size
  - Other: 0
  """
  def estimate_size(data) when is_binary(data), do: byte_size(data)
  def estimate_size(data) when is_list(data), do: length(data)
  def estimate_size(data) when is_map(data), do: map_size(data)
  def estimate_size(_data), do: 0

  @doc """
  Preserves the result tuple structure during transformation.

  Ensures errors remain as {:error, reason} and successes as {:ok, data}.
  """
  def preserve_structure({name, {:ok, data}}, transform_fn) do
    {name, {:ok, transform_fn.(data)}}
  end

  def preserve_structure({_name, {:error, _reason}} = error, _transform_fn) do
    error
  end
end
