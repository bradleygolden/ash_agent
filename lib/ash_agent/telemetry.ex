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
    :telemetry.execute([:ash_agent, event, :start], %{}, metadata)

    {result, meta} =
      case fun.() do
        {result, enriched_metadata} when is_map(enriched_metadata) ->
          {result, enriched_metadata}

        result ->
          {result, metadata}
      end

    stop_meta = stop_metadata(result, meta)

    emit_summary(event, stop_meta)
    :telemetry.execute([:ash_agent, event, :stop], %{}, stop_meta)

    {result, stop_meta}
  end

  defp stop_metadata({:ok, response}, metadata) do
    metadata =
      metadata
      |> maybe_put_usage(response)
      |> maybe_put_usage(Map.get(metadata, :response))
      |> maybe_put_usage(Map.get(metadata, :result))

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
    case LLMClient.response_usage(metadata[:provider], response) do
      nil -> metadata
      usage -> Map.put(metadata, :usage, usage)
    end
  end

  defp emit_summary(event, metadata) when event in [:call, :stream] do
    summary_meta =
      metadata
      |> Map.put(:kind, event)
      |> Map.put_new(:timestamp, DateTime.utc_now())

    :telemetry.execute([:ash_agent, event, :summary], %{}, summary_meta)
  end

  defp emit_summary(_event, _metadata), do: :ok
end
