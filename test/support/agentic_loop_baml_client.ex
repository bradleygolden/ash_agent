defmodule AshAgent.Test.AgenticLoopBamlClient do
  @moduledoc false

  defmodule AgentLoop do
    @moduledoc false

    def call(args, _opts \\ []) do
      iteration = extract_arg(args, :iteration) || 1

      response =
        if iteration >= 3 do
          %{intent: "done", answer: "Completed after #{iteration} iterations"}
        else
          %{intent: "search", query: "query for iteration #{iteration}"}
        end

      {:ok, response}
    end

    def stream(args, callback) do
      stream(args, callback, [])
    end

    def stream(args, callback, _opts) do
      {:ok, response} = call(args)

      pid =
        spawn(fn ->
          partial = if response.intent == "done", do: %{intent: "done"}, else: %{intent: "search"}
          callback.({:partial, partial})
          callback.({:done, response})
        end)

      {:ok, pid}
    end

    defp extract_arg(map, key) when is_map(map) do
      Map.get(map, key) || Map.get(map, Atom.to_string(key))
    end
  end
end
