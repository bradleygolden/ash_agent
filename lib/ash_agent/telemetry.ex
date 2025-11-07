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
      result = fun.()
      {result, stop_metadata(result, metadata)}
    end)
  end

  defp stop_metadata({:ok, response}, metadata) do
    metadata
    |> Map.put(:status, :ok)
    |> maybe_put_usage(response)
  end

  defp stop_metadata({:error, error}, metadata) do
    metadata
    |> Map.put(:status, :error)
    |> Map.put(:error, error)
  end

  defp maybe_put_usage(metadata, response) do
    case LLMClient.response_usage(response) do
      nil -> metadata
      usage -> Map.put(metadata, :usage, usage)
    end
  end
end
