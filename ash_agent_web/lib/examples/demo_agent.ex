defmodule Examples.DemoAgent do
  @moduledoc """
  A demonstration agent for testing the AshAgent Web UI.

  This agent has several tools to exercise different aspects of the monitoring dashboard.
  """

  use Ash.Resource,
    domain: Examples.TestDomain,
    extensions: [AshAgent.Resource]

  resource do
    require_primary_key? false
  end

  agent do
    provider :baml
    client :default, function: :AgentWithTools
    output AshAgentWeb.BamlClient.Types.ToolCallResponse

    input do
      argument :message, :string, allow_nil?: false
    end

    tools do
      max_iterations 5
      timeout 30_000
      on_error :continue

      tool :get_time do
        description "Gets the current time in UTC"

        function fn _args, _context ->
          {:ok, DateTime.utc_now() |> Calendar.strftime("%Y-%m-%d %H:%M:%S UTC")}
        end
      end

      tool :random_number do
        description "Generates a random number between min and max"

        parameters [
          min: [type: :integer, required: false, default: 1],
          max: [type: :integer, required: false, default: 100]
        ]

        function fn args, _context ->
          min = args[:min] || 1
          max = args[:max] || 100
          {:ok, Enum.random(min..max)}
        end
      end

      tool :echo do
        description "Echoes back the provided message"

        parameters [
          message: [type: :string, required: true]
        ]

        function fn args, _context ->
          {:ok, args.message}
        end
      end

      tool :calculate do
        description "Performs basic arithmetic (add, subtract, multiply, divide)"

        parameters [
          operation: [type: :atom, required: true],
          a: [type: :integer, required: true],
          b: [type: :integer, required: true]
        ]

        function fn args, _context ->
          result =
            case args.operation do
              :add -> args.a + args.b
              :subtract -> args.a - args.b
              :multiply -> args.a * args.b
              :divide when args.b != 0 -> args.a / args.b
              :divide -> {:error, "Cannot divide by zero"}
              _ -> {:error, "Unknown operation"}
            end

          case result do
            {:error, _} = err -> err
            value -> {:ok, value}
          end
        end
      end

      tool :submit_answer do
        description "Submit the final answer to complete the task. Use this when you have gathered all necessary information and are ready to provide the final response."

        parameters [
          answer: [type: :string, required: true, description: "The final answer to submit"],
          confidence: [type: :string, required: false, description: "Your confidence level (low/medium/high)"]
        ]

        function fn args, _context ->
          {:halt, %{
            answer: args.answer,
            confidence: args[:confidence] || "high",
            completed: true
          }}
        end
      end
    end
  end

  code_interface do
    define :call, args: [:message]
  end
end
