defmodule AshAgent do
  @moduledoc """
  ![Logo](https://github.com/bradleygolden/ash_agent/blob/main/logos/logo.png?raw=true)

  An Ash Framework extension for building AI agent applications with LLM integration.

  AshAgent provides a declarative DSL for defining AI agents as Ash resources,
  enabling seamless integration of LLM capabilities into your Ash applications.

  ## Installation

  Add `ash_agent` to your list of dependencies in `mix.exs`:

  ```elixir
  def deps do
    [
      {:ash_agent, "~> 0.1.0"}
    ]
  end
  ```

  ## Getting Started

  AshAgent provides two main extensions:

  - `AshAgent.Resource` - Add agent capabilities to your Ash resources
  - `AshAgent.Domain` - Configure agent behavior at the domain level

  See the [Getting Started guide](documentation/tutorials/getting-started.md) for more information.

  ## Features

  - Declarative agent definition using Spark DSL
  - Integration with Ash resources and domains
  - Type-safe configuration
  - Extensible architecture

  ## Links

  - [Source Code](https://github.com/bradleygolden/ash_agent)
  - [Documentation](https://hexdocs.pm/ash_agent)
  """
end
