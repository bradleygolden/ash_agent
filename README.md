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

### 1. Define an Output Type

```elixir
defmodule MyApp.Reply do
  use Ash.TypedStruct

  typed_struct do
    field :content, :string, allow_nil?: false
  end
end
```

### 2. Define an Agent Resource

```elixir
defmodule MyApp.Assistant do
  use Ash.Resource,
    domain: MyApp.Agents,
    extensions: [AshAgent.Resource]

  agent do
    client "anthropic:claude-sonnet-4-20250514"
    output MyApp.Reply

    prompt ~p"""
    You are a helpful assistant.

    {{ output_format }}

    User: {{ message }}
    """

    input do
      argument :message, :string, allow_nil?: false
    end
  end
end
```

### 3. Configure Your Domain

```elixir
defmodule MyApp.Agents do
  use Ash.Domain

  resources do
    resource MyApp.Assistant
  end
end
```

Optionally add `AshAgent.Domain` extension for auto-generated code interfaces:

```elixir
defmodule MyApp.Agents do
  use Ash.Domain,
    extensions: [AshAgent.Domain]

  resources do
    resource MyApp.Assistant
  end
end

# Generates: MyApp.Agents.call_assistant("Hello!")
# Generates: MyApp.Agents.stream_assistant("Hello!")
```

### 4. Call Your Agent

```elixir
# Via Ash action
{:ok, reply} = MyApp.Assistant
|> Ash.ActionInput.for_action(:call, %{message: "Hello!"})
|> Ash.run_action()

reply.content
#=> "Hello! How can I help you today?"

# Or stream responses
{:ok, stream} = MyApp.Assistant
|> Ash.ActionInput.for_action(:stream, %{message: "Hello!"})
|> Ash.run_action()

Enum.each(stream, &IO.inspect/1)
```

## DSL Reference

### `agent` Section

| Option | Type | Required | Description |
|--------|------|----------|-------------|
| `client` | string/atom | Yes | LLM provider and model (e.g., `"anthropic:claude-sonnet-4-20250514"`) |
| `output` | module | Yes | `Ash.TypedStruct` module for response type |
| `prompt` | string/template | Depends | Liquid template for system prompt. Use `~p` sigil for compile-time validation. Required unless provider declares `:prompt_optional`. |
| `provider` | atom | No | LLM provider (`:req_llm` default, `:baml`, or custom module) |
| `hooks` | module | No | Module implementing `AshAgent.Runtime.Hooks` behaviour |
| `token_budget` | integer | No | Maximum tokens for agent execution |
| `budget_strategy` | `:halt` or `:warn` | No | How to handle budget limits (default: `:warn`) |

### `input` Section (Optional)

Define input arguments that get passed to the prompt template:

```elixir
agent do
  # ...
  input do
    argument :message, :string, allow_nil?: false
    argument :context, :map, default: %{}
  end
end
```

If you don't define an `input` section, the agent accepts a single `input` map argument.

## Provider Options

AshAgent supports multiple LLM providers through an abstraction layer.

### ReqLLM (Default)

```elixir
agent do
  provider :req_llm
  client "anthropic:claude-sonnet-4-20250514", temperature: 0.7, max_tokens: 1000
  # ...
end
```

### BAML (Optional)

For structured outputs via [ash_baml](https://github.com/bradleygolden/ash_baml):

```elixir
agent do
  provider :baml
  client :my_client, function: :ChatAgent
  output MyApp.BamlClient.Types.Response
  # prompt is optional with BAML provider
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
