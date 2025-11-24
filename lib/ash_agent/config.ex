defmodule AshAgent.Config do
  @moduledoc """
  Application configuration for AshAgent.

  This module provides centralized access to application-level configuration
  that is not part of the DSL. Configuration is read from the `:ash_agent`
  application environment.

  ## Configuration Options

  - `:context_module` - The module to use for building execution contexts.
    Defaults to the built-in context module. Extension packages may override
    this to inject additional context fields.

  ## Examples

      # In config/config.exs
      config :ash_agent,
        context_module: MyApp.CustomContext

      # Runtime access
      AshAgent.Config.context_module()
      #=> MyApp.CustomContext
  """

  @doc """
  Get the configured context module.

  Returns the module to use for building execution contexts. Extension
  packages may override this to inject their own context module with
  additional fields or behaviors.

  Extension packages register their context module via the RuntimeRegistry:

      AshAgent.RuntimeRegistry.register_context_module(MyExtension.Context)

  Defaults to the built-in context module if not registered.

  ## Examples

      # With registered extension context
      AshAgent.RuntimeRegistry.register_context_module(MyApp.CustomContext)
      AshAgent.Config.context_module()
      #=> MyApp.CustomContext
  """
  @spec context_module() :: module()
  def context_module do
    AshAgent.RuntimeRegistry.get_context_module()
  end
end
