# AshAgent

[![Hex.pm](https://img.shields.io/hexpm/v/ash_agent.svg)](https://hex.pm/packages/ash_agent)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> **Pre-1.0 Release** - API may change between minor versions. Pin to specific versions in production.

**Production AI agents for Elixir.** AshAgent builds on Ash Framework to give you durable state, authorization, and declarative agent definitions—without locking you into any specific LLM provider.

## Installation

```elixir
def deps do
  [
    {:ash_agent, "~> 0.1.0"}
  ]
end
```

## Quick Start

### 1. Define an Agent Resource

```elixir
defmodule MyApp.Assistant do
  use Ash.Resource,
    domain: MyApp.Agents,
    extensions: [AshAgent.Resource]

  agent do
    client "anthropic:claude-sonnet-4-20250514"

    instruction ~p"""
    You are a helpful assistant for {{ company_name }}.
    """

    instruction_schema Zoi.object(%{
      company_name: Zoi.string()
    }, coerce: true)

    input_schema Zoi.object(%{message: Zoi.string()}, coerce: true)

    output_schema Zoi.object(%{content: Zoi.string()}, coerce: true)
  end

  code_interface do
    define :call, args: [:context]
    define :stream, args: [:context]
  end
end
```

### 2. Configure Your Domain

```elixir
defmodule MyApp.Agents do
  use Ash.Domain

  resources do
    resource MyApp.Assistant
  end
end
```

### 3. Call Your Agent

AshAgent uses a context-based API for building conversations:

```elixir
# Build context with instruction and user message
context =
  [
    MyApp.Assistant.instruction(company_name: "Acme Corp"),
    MyApp.Assistant.user(message: "Hello!")
  ]
  |> MyApp.Assistant.context()

# Call the agent
{:ok, result} = MyApp.Assistant.call(context)
result.output.content
#=> "Hello! How can I help you today?"

# For multi-turn conversations, reuse the context from the result
new_context =
  [
    result.context,
    MyApp.Assistant.user(message: "What's the weather?")
  ]
  |> MyApp.Assistant.context()

{:ok, result2} = MyApp.Assistant.call(new_context)
```

### Streaming Responses

```elixir
context =
  [
    MyApp.Assistant.instruction(company_name: "Acme Corp"),
    MyApp.Assistant.user(message: "Tell me a story")
  ]
  |> MyApp.Assistant.context()

{:ok, stream} = MyApp.Assistant.stream(context)

Enum.each(stream, fn chunk ->
  IO.write(chunk.content)
end)
```

## Generated Functions

AshAgent generates these functions on your agent module:

- `context/1` - Wraps a list of messages into an `AshAgent.Context`
- `instruction/1` - Creates a system message (validates against instruction_schema)
- `user/1` - Creates a user message (validates against input_schema)

## DSL Reference

### `agent` Section

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `client` | string/atom | Yes | LLM provider and model (e.g., `"anthropic:claude-sonnet-4-20250514"`) |
| `instruction` | string/template | Depends | System instruction template. Use `~p` sigil for Liquid templates. Required unless provider declares `:prompt_optional`. |
| `instruction_schema` | Zoi schema | No | Zoi schema for instruction template arguments |
| `input_schema` | Zoi schema | Yes | Zoi schema for user message validation |
| `output_schema` | Zoi schema | Yes | Zoi schema for output validation and structured output enforcement |
| `provider` | atom | No | LLM provider (`:req_llm` default, `:baml`, or custom module) |
| `hooks` | module | No | Module implementing `AshAgent.Runtime.Hooks` behaviour |
| `token_budget` | integer | No | Maximum tokens for agent execution |
| `budget_strategy` | `:halt` or `:warn` | No | How to handle budget limits (default: `:warn`) |

Structured output is handled automatically by the provider—Zoi schemas are compiled to JSON Schema and passed to the LLM API.

## Provider Options

AshAgent supports multiple LLM providers through an abstraction layer.

### ReqLLM (Default)

```elixir
agent do
  provider :req_llm
  client "anthropic:claude-sonnet-4-20250514", temperature: 0.7, max_tokens: 1000
  instruction "You are a helpful assistant."
  input_schema Zoi.object(%{message: Zoi.string()})
  output_schema Zoi.object(%{content: Zoi.string()})
end
```

### BAML (Optional)

For structured outputs via [ash_baml](https://github.com/bradleygolden/ash_baml):

```elixir
agent do
  provider :baml
  client :my_client, function: :ChatAgent
  instruction "Prompt defined in BAML"
  input_schema Zoi.object(%{message: Zoi.string()})
  output_schema MyBamlTypes.ChatReply
end
```

### Custom Providers

Register custom providers in config:

```elixir
config :ash_agent,
  providers: [
    custom: MyApp.CustomProvider
  ]
```

## Generated Actions

AshAgent automatically generates two actions on your resource:

- `:call` - Synchronous LLM call returning structured response
- `:stream` - Streaming LLM call returning enumerable of partial responses

These integrate with Ash's action system, enabling authorization policies, preparations, and all standard Ash action features.

## Telemetry

AshAgent emits telemetry events for observability:

- `[:ash_agent, :call, :start | :stop | :exception | :summary]`
- `[:ash_agent, :stream, :start | :chunk | :summary | :stop]`
- `[:ash_agent, :prompt, :rendered]`
- `[:ash_agent, :llm, :request | :response | :error]`

## Development

```bash
mix test
mix format
mix credo --strict
mix dialyzer
```

## License

MIT License - see [LICENSE](LICENSE) for details.

## Related Packages

AshAgent is part of the [AshAgent Stack](https://github.com/bradleygolden/ash_agent_stack) ecosystem:

- [ash_baml](https://github.com/bradleygolden/ash_baml) - BAML integration for structured outputs
- [ash_agent_tools](https://github.com/bradleygolden/ash_agent_tools) - Tool calling support

## Links

- [GitHub](https://github.com/bradleygolden/ash_agent)
- [AshAgent Stack](https://github.com/bradleygolden/ash_agent_stack)
- [Ash Framework](https://ash-hq.org/)
