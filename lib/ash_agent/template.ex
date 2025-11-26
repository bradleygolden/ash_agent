defmodule AshAgent.Template do
  @moduledoc """
  DSL for defining composable agent templates as Spark fragments.

  Templates are fragments of `Ash.Resource` that provide agent configuration
  (output, inputs, prompt) but not client/provider. They can be used in two ways:

  ## Quick Start Mode

  Register the template in your domain to generate a real agent:

      defmodule MyApp.Agents do
        use Ash.Domain, extensions: [AshAgent.Domain]

        agents do
          agent AshAgentMarketplace.Agents.TitleGenerator,
            client: "openai:gpt-4o"
        end
      end

  This generates `MyApp.Agents.TitleGenerator` as a real agent module.

  ## Full Control Mode

  Use the template as a fragment in your own resource for full customization:

      defmodule MyApp.Agents.CustomTitleGenerator do
        use Ash.Resource,
          domain: MyApp.Agents,
          extensions: [AshAgent.Resource, AshOban],
          fragments: [AshAgentMarketplace.Agents.TitleGenerator]

        agent do
          client "openai:gpt-4o"
          hooks MyApp.CustomHooks
        end

        attributes do
          uuid_primary_key :id
          timestamps()
        end

        oban do
          triggers do
            trigger :process, action: :call
          end
        end
      end

  ## Defining a Template

  Templates use the same `agent` DSL as resources, minus client/provider:

      defmodule MyMarketplace.Agents.TitleGenerator do
        use AshAgent.Template

        agent do
          output :string

          input do
            argument :text, :string, allow_nil?: false
          end

          prompt ~p"Generate a title for: {{ text }}"
        end
      end
  """

  defmacro __using__(_opts) do
    quote do
      use Spark.Dsl.Fragment,
        of: Ash.Resource,
        extensions: [AshAgent.Template.Dsl]
    end
  end
end
