defmodule AshAgent.Telemetry do
  @moduledoc """
  Convenience wrappers around `:telemetry` for AshAgent runtime events.

  Emits spans for `[:ash_agent, :call]` and `[:ash_agent, :stream]`, enriching metadata
  with provider usage metrics when available.
  """

  alias AshAgent.Runtime.LLMClient

  @type span_event :: :call | :stream

  @doc """
  Executes `fun` within a telemetry span for the given event.

  `metadata` should include at least `:agent`, `:provider`, and `:client`.
  """
  @spec span(span_event(), map(), (-> any())) :: any()
  def span(event, metadata, fun) when event in [:call, :stream] do
    :telemetry.span([:ash_agent, event], metadata, fn ->
      case fun.() do
        {result, enriched_metadata}
        when is_map(enriched_metadata) and not is_map_key(enriched_metadata, :__struct__) ->
          {result, stop_metadata(result, enriched_metadata)}

        result ->
          {result, stop_metadata(result, metadata)}
      end
    end)
  end

  defp stop_metadata({:ok, response}, metadata) do
    metadata =
      if Map.has_key?(metadata, :usage) do
        metadata
      else
        response_for_usage = Map.get(metadata, :response, response)
        maybe_put_usage(metadata, response_for_usage)
      end

    Map.put(metadata, :status, :ok)
  end

  defp stop_metadata({:error, error}, metadata) do
    metadata
    |> Map.put(:status, :error)
    |> Map.put(:error, error)
  end

  defp stop_metadata(_result, metadata) do
    Map.put(metadata, :status, :unknown)
  end

  defp maybe_put_usage(metadata, response) do
    case LLMClient.response_usage(response) do
      nil -> metadata
      usage -> Map.put(metadata, :usage, usage)
    end
  end
end
