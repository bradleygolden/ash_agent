defmodule AshAgent.Metadata do
  @moduledoc """
  Unified metadata container for provider responses.

  Captures timing, tracing, costs, and provider-specific data in a type-safe struct.
  This enables consistent metadata tracking across all providers (ReqLLM, BAML, Mock).

  ## Fields

  ### Timing
  - `:duration_ms` - Total call duration in milliseconds (captured by runtime)
  - `:time_to_first_token_ms` - Time to first token for streaming (BAML only currently)
  - `:started_at` - UTC datetime when call started
  - `:completed_at` - UTC datetime when call completed

  ### Request Tracing
  - `:request_id` - Unique request identifier (BAML)
  - `:provider` - Provider atom (:req_llm, :baml, :mock)
  - `:client_name` - BAML client name

  ### Execution Details
  - `:num_attempts` - Number of retry attempts (BAML)
  - `:tags` - Custom metadata tags (BAML)

  ### Extended Usage (beyond Result.usage)
  - `:reasoning_tokens` - Tokens used for reasoning (o1/o3 models via ReqLLM)
  - `:cached_tokens` - Cached input tokens (Anthropic via ReqLLM)
  - `:input_cost` - Cost for input tokens (ReqLLM)
  - `:output_cost` - Cost for output tokens (ReqLLM)
  - `:total_cost` - Total cost (ReqLLM)

  ### Debug Data
  - `:raw_http_response` - Raw HTTP response body for debugging (BAML)

  ## Example

      %AshAgent.Metadata{
        duration_ms: 1234,
        started_at: ~U[2025-01-15 10:00:00Z],
        completed_at: ~U[2025-01-15 10:00:01.234Z],
        provider: :req_llm,
        reasoning_tokens: 64,
        total_cost: 0.0025
      }
  """

  @derive Jason.Encoder
  defstruct [
    :duration_ms,
    :time_to_first_token_ms,
    :started_at,
    :completed_at,
    :request_id,
    :provider,
    :client_name,
    :num_attempts,
    :tags,
    :reasoning_tokens,
    :cached_tokens,
    :input_cost,
    :output_cost,
    :total_cost,
    :raw_http_response
  ]

  @type t :: %__MODULE__{
          duration_ms: non_neg_integer() | nil,
          time_to_first_token_ms: non_neg_integer() | nil,
          started_at: DateTime.t() | nil,
          completed_at: DateTime.t() | nil,
          request_id: String.t() | nil,
          provider: atom() | nil,
          client_name: String.t() | nil,
          num_attempts: non_neg_integer() | nil,
          tags: map() | nil,
          reasoning_tokens: non_neg_integer() | nil,
          cached_tokens: non_neg_integer() | nil,
          input_cost: Decimal.t() | float() | nil,
          output_cost: Decimal.t() | float() | nil,
          total_cost: Decimal.t() | float() | nil,
          raw_http_response: String.t() | nil
        }

  @doc """
  Creates a new Metadata struct, merging provider data with runtime timing.

  Provider metadata is extracted from the provider's `extract_metadata/1` callback,
  and runtime timing is captured by the AshAgent runtime.

  ## Parameters

  - `provider_metadata` - Map of metadata from the provider
  - `runtime_timing` - Map with `:started_at`, `:completed_at`, `:duration_ms`

  ## Example

      iex> AshAgent.Metadata.new(%{provider: :req_llm, total_cost: 0.01}, %{duration_ms: 500})
      %AshAgent.Metadata{provider: :req_llm, total_cost: 0.01, duration_ms: 500}
  """
  def new(provider_metadata \\ %{}, runtime_timing \\ %{}) do
    merged = Map.merge(to_map(provider_metadata), to_map(runtime_timing))
    struct(__MODULE__, merged)
  end

  defp to_map(data) when is_map(data), do: data
  defp to_map(data) when is_list(data), do: Map.new(data)
  defp to_map(_), do: %{}
end
