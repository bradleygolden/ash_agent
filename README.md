# AshAgent

![Elixir CI](https://github.com/bradleygolden/ash_agent/workflows/Elixir%20CI/badge.svg)
[![Hex version badge](https://img.shields.io/hexpm/v/ash_agent.svg)](https://hex.pm/packages/ash_agent)
[![Hexdocs badge](https://img.shields.io/badge/docs-hexdocs-purple)](https://hexdocs.pm/ash_agent)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

An Ash Framework extension for building AI agent applications with LLM integration.

AshAgent provides a declarative DSL for defining AI agents as Ash resources, enabling seamless integration of LLM capabilities into your Ash applications.

## Features

- 🎯 **Declarative Agent Definition** - Define agents using Spark DSL
- 🔧 **Resource & Domain Extensions** - Integrate at both resource and domain levels
- 🛡️ **Type-Safe Configuration** - Compile-time validation of all configuration
- 🚀 **Built on Ash** - Leverage all Ash features (actions, policies, pubsub, etc.)
- 📚 **Well Documented** - Comprehensive guides and API documentation
- ⚡ **Extensible** - Add custom transformers and verifiers

## Installation

Add `ash_agent` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ash_agent, "~> 0.1.0"}
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

```elixir
# Create an agent
{:ok, agent} = MyApp.Agents.Assistant
  |> Ash.Changeset.for_create(:create, %{name: "My Assistant"})
  |> Ash.create()
```

## Documentation

- [Getting Started Guide](documentation/tutorials/getting-started.md)
- [Overview & Concepts](documentation/topics/overview.md)
- [Full Documentation](https://hexdocs.pm/ash_agent)

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
- [Documentation](https://hexdocs.pm/ash_agent)
- [Hex Package](https://hex.pm/packages/ash_agent)
- [Changelog](CHANGELOG.md)

