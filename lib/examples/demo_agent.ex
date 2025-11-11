defmodule Examples.DemoAgent do
  @moduledoc """
  A demonstration agent for testing the AshAgent Web UI.

  This agent has several tools to exercise different aspects of the monitoring dashboard.
  """

  use Ash.Resource,
    domain: Examples.TestDomain,
    extensions: [AshAgent.Resource]

  agent do
    client "anthropic:claude-3-5-sonnet"
    output :string
    prompt """
    You are a helpful assistant. Use the available tools when appropriate.
    Always be concise in your responses.
    """
  end

  tools do
    tool :get_time do
      description "Gets the current time in UTC"

      code fn _args, _context ->
        {:ok, DateTime.utc_now() |> Calendar.strftime("%Y-%m-%d %H:%M:%S UTC")}
      end
    end

    tool :random_number do
      description "Generates a random number between min and max"

      argument :min, :integer do
        default 1
      end

      argument :max, :integer do
        default 100
      end

      code fn args, _context ->
        min = args[:min] || 1
        max = args[:max] || 100
        {:ok, Enum.random(min..max)}
      end
    end

    tool :echo do
      description "Echoes back the provided message"

      argument :message, :string, allow_nil?: false

      code fn args, _context ->
        {:ok, args.message}
      end
    end

    tool :calculate do
      description "Performs basic arithmetic (add, subtract, multiply, divide)"

      argument :operation, :atom, allow_nil?: false
      argument :a, :integer, allow_nil?: false
      argument :b, :integer, allow_nil?: false

      code fn args, _context ->
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
  end

  attributes do
    attribute :question, :string do
      allow_nil? false
      public? true
    end
  end

  actions do
    default_read_action :read
    default_create_action :create
  end

  code_interface do
    define :call, args: [:question]
  end
end
