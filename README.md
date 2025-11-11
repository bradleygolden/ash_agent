# AshAgent

![Elixir CI](https://github.com/bradleygolden/ash_agent/workflows/Elixir%20CI/badge.svg)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

> ⚠️ This project is experimental and not yet published to Hex; expect rapid changes and install directly from Git.

An Ash Framework extension for building AI agent applications with LLM integration.

AshAgent provides a declarative DSL for defining AI agents as Ash resources, enabling seamless integration of LLM capabilities into your Ash applications.

## Features

- 🎯 **Declarative Agent Definition** - Define agents using Spark DSL
- 🔧 **Resource & Domain Extensions** - Integrate at both resource and domain levels
- 🛡️ **Type-Safe Configuration** - Compile-time validation of all configuration
- 🚀 **Built on Ash** - Leverage all Ash features (actions, policies, pubsub, etc.)
- 📚 **Well Documented** - Comprehensive guides and API documentation
- ⚡ **Extensible** - Add custom transformers and verifiers
- 🔌 **Provider-Agnostic** - Works with ReqLLM, ash_baml, or custom providers

## Installation

Add `ash_agent` to your list of dependencies in `mix.exs` (Git dependency until the Hex release lands):

```elixir
def deps do
  [
    {:ash_agent, github: "bradleygolden/ash_agent", branch: "main"}
  ]
end
```

Then run:

```bash
mix deps.get
```

## Quick Start

### 1. Define an Agent Resource

```elixir
defmodule MyApp.Agents.Assistant do
  use Ash.Resource,
    domain: MyApp.Agents,
    extensions: [AshAgent.Resource]

  agent do
    client "anthropic:claude-3-5-sonnet"

    output MyApp.Reply

    prompt ~p"""
    You are a helpful assistant.
    {{ output_format }}
    """
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
  end
end
```

### 2. Configure Your Domain

```elixir
defmodule MyApp.Agents do
  use Ash.Domain,
    extensions: [AshAgent.Domain]

  resources do
    resource MyApp.Agents.Assistant
  end
end
```

### 3. Use Your Agent

When you declare an agent, AshAgent injects `:call` and `:stream` actions so you can invoke it like any other Ash resource action (or expose them via a `code_interface`).

```elixir
# Synchronous call with keyword args
{:ok, reply} = MyApp.Agents.Assistant.call(message: "Hello!")

# Stream partial responses
MyApp.Agents.Assistant.stream(message: "Hello!")
|> Enum.to_list()
```

## Documentation

- API Reference: `mix docs && open doc/index.html`

## Roadmap

- [ ] Context Management
  - [x] Tool calling support
  - [x] Iteration-based context tracking
  - [x] Structured message history
  - [x] Token budget management
  - [x] Context compaction/summarization
  - [x] Progressive disclosure for large tool results
  - [ ] External memory persistence
- [ ] Agent chaining
- [ ] Advanced orchestration (parallel execution, routing, DSL)

### Needs Research

- [ ] Tool result caching and lookup
- [ ] Guardrails & safety hooks
- [ ] Structured prompt segmentation (XML/Markdown sections)
- [ ] Evaluation harness for agents
- [ ] Observability dashboards
- [ ] MCP server support

## Provider Options

AshAgent ships with a provider abstraction so the orchestration layer is decoupled
from any specific LLM stack.

### ReqLLM (default)

The default `:req_llm` provider requires only a `provider:model` string:

```elixir
agent do
  provider :req_llm
  client "anthropic:claude-3-5-sonnet", temperature: 0.5
end
```

### ash_baml

AshAgent can delegate execution to [ash_baml](https://github.com/bradleygolden/ash_baml)
by switching to the `:baml` provider. Configure your BAML clients once:

```elixir
# config/config.exs
config :ash_baml,
  clients: [
    support: {MyApp.BamlClients.Support, baml_src: "baml_src/support"}
  ]
```

Then reference the client identifier inside your agent:

```elixir
agent do
  provider :baml
  client :support, function: :ChatAgent
  output MyApp.BamlClients.Support.Types.ChatAgent
end
```

You can also set `client_module: MyApp.BamlClients.Support` if you prefer to reference
the compiled module directly. Streaming is supported when your BAML function implements
`stream/2`.

Because BAML functions already carry their own prompts, the `:baml` provider declares
`:prompt_optional`, allowing you to omit the `prompt` DSL entirely. Providers that do not
declare this capability (e.g., `:req_llm`) will still require a prompt at compile time.

### Telemetry

AshAgent emits Telemetry spans for every provider interaction:

- `[:ash_agent, :call]` – fires around synchronous calls
- `[:ash_agent, :stream]` – fires when streaming sessions are opened

Metadata includes `:agent`, `:provider`, `:client`, `:status`, and (when available) token usage.
Attach handlers with `:telemetry.attach/4` to feed dashboards or observability pipelines.

## Development

### Running Tests

```bash
mix test
```

### Code Quality

```bash
# Format code
mix format

# Run Credo
mix credo --strict

# Run Dialyzer (first time will be slow)
mix dialyzer
```

### Generate Documentation

```bash
mix docs
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License.

## Acknowledgments

- Built with [Ash Framework](https://ash-hq.org/)
- Powered by [Spark DSL](https://github.com/ash-project/spark)

## Links

- [Source Code](https://github.com/bradleygolden/ash_agent)
