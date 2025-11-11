# AshAgent Web UI - Prototype

A minimal Phoenix LiveView dashboard for monitoring AshAgent executions in real-time.

## Features

- **Interactive agent testing** - Call agents directly from the UI with a built-in form
- **Conversation history** - See your questions and agent responses in a chat-like interface
- **Real-time monitoring** via telemetry and PubSub
- **Token tracking** with cost estimation per call and cumulative
- **Call history** with status and timing
- **Active call tracking** to see agents in progress with loading indicators
- **Simple metrics** dashboard showing totals

## Installation

This is a standalone Phoenix app that depends on the parent `ash_agent` library via path dependency.

### 1. Install dependencies

```bash
cd ash_agent_web
mix deps.get
```

### 2. Start the server

```bash
mix phx.server
```

The dashboard will be available at http://localhost:4001

### 3. Monitor your agents

Navigate to: http://localhost:4001/agents/YourAgentModule

For example, if you have a module called `MyApp.WeatherAgent`, visit:
http://localhost:4001/agents/Elixir.MyApp.WeatherAgent

## Usage Example

Here's a complete example to test the dashboard:

### 1. Create a test agent in your parent project

```elixir
# In your main ash_agent project (not in ash_agent_web)
# lib/examples/test_agent.ex

defmodule Examples.TestAgent do
  use Ash.Resource,
    domain: Examples.TestDomain,
    extensions: [AshAgent.Resource]

  agent do
    client "anthropic:claude-3-5-sonnet"
    output :string
    prompt "You are a helpful assistant. Answer the user's question concisely."
  end

  tools do
    tool :get_time do
      description "Gets the current time"

      code fn _args, _context ->
        {:ok, DateTime.utc_now() |> to_string()}
      end
    end

    tool :random_number do
      description "Generates a random number between 1 and 100"

      code fn _args, _context ->
        {:ok, Enum.random(1..100)}
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
end
```

### 2. Call your agent

```elixir
# From IEx in your main project
iex -S mix

# Make some calls to generate data
Examples.TestAgent.call!(%{question: "What time is it?"})
Examples.TestAgent.call!(%{question: "Give me a random number"})
Examples.TestAgent.call!(%{question: "What's 2+2?"})
```

### 3. Watch the dashboard update

While the agents are running, watch the dashboard at:
http://localhost:4001/agents/Elixir.Examples.TestAgent

You'll see:
- Active calls appear in real-time
- Metrics update as calls complete
- Token usage accumulate
- Cost estimates calculate automatically

## How It Works

### Telemetry Collection

The dashboard attaches to ash_agent telemetry events:
- `[:ash_agent, :call, :start]` - Call begins
- `[:ash_agent, :call, :stop]` - Call completes successfully
- `[:ash_agent, :call, :exception]` - Call fails
- `[:ash_agent, :token_limit_warning]` - Token threshold exceeded

### Data Storage

Currently uses **in-memory ETS tables** for simplicity:
- `:ash_agent_calls` - Active and recent calls
- `:ash_agent_metrics` - Aggregated statistics per agent

For production use, you'd want to persist this to a database.

### Real-time Updates

Uses Phoenix.PubSub to broadcast events from telemetry handlers to LiveView:
- Each agent has a topic: `"agent:#{agent_module}"`
- LiveView subscribes on mount
- Updates appear instantly as calls progress

### Cost Estimation

Currently hardcoded for Claude 3.5 Sonnet pricing:
- Input: $3.00 per million tokens
- Output: $15.00 per million tokens

Modify `AshAgentWeb.Telemetry.estimate_cost/1` to support other models.

## Architecture

```
User Browser
    ↓
Phoenix LiveView (AgentLive)
    ↓ subscribes to
PubSub Topic ("agent:MyAgent")
    ↑ broadcasts
Telemetry Handler
    ↑ receives
AshAgent Runtime (telemetry events)
```

## Customization

### Adding More Metrics

Edit `AshAgentWeb.Telemetry.update_metrics/2` to track additional data.

### Different Cost Models

Update `estimate_cost/1` to handle different providers:

```elixir
defp estimate_cost(usage, provider) do
  rates = %{
    "anthropic:claude-3-5-sonnet" => {3.0, 15.0},
    "openai:gpt-4" => {10.0, 30.0}
  }

  {input_rate, output_rate} = Map.get(rates, provider, {0.0, 0.0})
  # ... calculate cost
end
```

### Persisting History

Replace ETS with an Ash resource for permanent storage.

## Limitations (Prototype)

- In-memory storage only (restarts lose history)
- No authentication/authorization
- Single-agent view only (no multi-agent dashboard)
- Simplified cost calculation
- No detailed iteration/message inspection (yet)

## Next Steps

For a production-ready version:

1. Add database persistence (Postgres + Ash resources)
2. Build multi-agent dashboard homepage
3. Add detailed call inspector (view full messages/context)
4. Implement filtering and search
5. Add charts for historical trends
6. Support custom cost models per provider
7. Add authentication
8. Package as a mountable Phoenix component (like ash_admin)
