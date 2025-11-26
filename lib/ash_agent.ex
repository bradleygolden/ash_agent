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

  ## Extensions

  - `AshAgent.Resource` - Add agent capabilities to your Ash resources
  - `AshAgent.Domain` - Auto-generate code interfaces for agent resources

  ## Features

  - Declarative agent definition using Spark DSL
  - Integration with Ash resources and domains
  - Type-safe configuration
  - Extensible architecture
  - Hook system for customizing agent behavior

  ## Customizing Agent Behavior

  AshAgent provides a hook system for extending and customizing agent behavior
  at runtime. Hooks allow you to intercept the agent execution lifecycle:

  - `before_call` - Called before rendering the prompt
  - `after_render` - Called after prompt rendering, before LLM call
  - `after_call` - Called after successful LLM response
  - `on_error` - Called when any error occurs

  See `AshAgent.Runtime.Hooks` for complete documentation.

  ## Links

  - [Source Code](https://github.com/bradleygolden/ash_agent)
  - [Documentation](https://hexdocs.pm/ash_agent)
  """
end
