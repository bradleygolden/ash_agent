defmodule AshAgent.Integration.AgenticLoop.ReqLLM.OllamaTest do
  @moduledoc false
  use AshAgent.IntegrationCase, backend: :req_llm, provider: :ollama

  alias AshAgent.Runtime

  defmodule TestDomain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      allow_unregistered? true
    end
  end

  defmodule LoopAgent do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.Integration.AgenticLoop.ReqLLM.OllamaTest.TestDomain,
      extensions: [AshAgent.Resource]

    import AshAgent.Sigils

    resource do
      require_primary_key? false
    end

    agent do
      client("openai:qwen3:1.7b",
        base_url: "http://localhost:11434/v1",
        api_key: "ollama",
        temperature: 0.0
      )

      input_schema(
        Zoi.object(%{message: Zoi.string(), iteration: Zoi.integer() |> Zoi.optional()},
          coerce: true
        )
      )

      output_schema(
        Zoi.union([
          Zoi.object(%{intent: Zoi.literal("search"), query: Zoi.string()}, coerce: true),
          Zoi.object(%{intent: Zoi.literal("done"), answer: Zoi.string()}, coerce: true)
        ])
      )

      instruction(~p"""
      Help the user. Current iteration: {{ iteration }}.
      Task: {{ message }}

      Respond with JSON matching one of the output types:
      - If iteration < 3: {"intent": "search", "query": "<search query>"}
      - If iteration >= 3: {"intent": "done", "answer": "<final answer>"}

      {{ ctx.output_format }}
      """)
    end
  end

  setup do
    ReqLLM.put_key(:openai_api_key, "ollama")

    original_opts = Application.get_env(:ash_agent, :req_llm_options, [])
    Application.put_env(:ash_agent, :req_llm_options, [])

    on_exit(fn ->
      Application.put_env(:ash_agent, :req_llm_options, original_opts)
    end)

    :ok
  end

  defp run_agentic_loop(agent, initial_args, opts \\ []) do
    max_iterations = Keyword.get(opts, :max_iterations, 10)
    run_loop(agent, initial_args, [], 1, max_iterations)
  end

  defp run_loop(_agent, _args, results, iteration, max) when iteration > max do
    {:error, :max_iterations_exceeded, Enum.reverse(results)}
  end

  defp run_loop(agent, args, results, iteration, max) do
    args_with_iteration = Map.put(args, :iteration, iteration)

    case Runtime.call(agent, args_with_iteration) do
      {:ok, %AshAgent.Result{output: output} = result} ->
        new_results = [result | results]

        case output.intent do
          "done" ->
            {:ok, Enum.reverse(new_results)}

          "search" ->
            run_loop(agent, args, new_results, iteration + 1, max)

          _ ->
            {:error, :unexpected_intent, Enum.reverse(new_results)}
        end

      {:error, reason} ->
        {:error, reason, Enum.reverse(results)}
    end
  end

  test "loops until agent returns done intent" do
    {:ok, results} = run_agentic_loop(LoopAgent, %{message: "find something"})

    assert length(results) >= 1

    last_result = List.last(results)
    assert last_result.output.intent == "done"

    if length(results) > 1 do
      intermediate_results = Enum.slice(results, 0..-2//1)
      assert Enum.all?(intermediate_results, fn r -> r.output.intent == "search" end)
    end
  end
end
