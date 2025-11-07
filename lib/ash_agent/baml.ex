defmodule AshAgent.Baml do
  @moduledoc """
  Helper macros for configuring `:baml` providers inside an `agent` block.

  ## Examples

      defmodule MyApp.BamlAgent do
        use Ash.Resource,
          extensions: [AshAgent.Resource]

        import AshAgent.Baml

        agent do
          baml_provider :support, :ChatAgent
          output MyApp.BamlClients.Support.Types.ChatAgent
          prompt \"\"\"Prompt is ignored by BAML but required by the DSL\"\"\"
        end
      end
  """

  @doc """
  Configures the agent to use the `:baml` provider with the given client identifier
  (or client module) and function name.

  Additional options are merged into the `client` configuration.
  """
  defmacro baml_provider(client_identifier, function_name, opts \\ []) do
    quote do
      provider(:baml)

      client(
        unquote(client_identifier),
        Keyword.merge([function: unquote(function_name)], unquote(opts))
      )
    end
  end
end
