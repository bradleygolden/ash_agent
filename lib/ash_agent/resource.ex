defmodule AshAgent.Resource do
  @moduledoc """
  The AshAgent resource extension.

  This extension allows you to define LLM agents as Ash resources with type-safe
  inputs/outputs, instruction templates, and automatic action generation.

  ## Usage

  Define an agent resource:

  ```elixir
  defmodule MyApp.ChatAgent do
    use Ash.Resource,
      domain: MyApp.Domain,
      extensions: [AshAgent.Resource]

    agent do
      client "anthropic:claude-sonnet-4-20250514", temperature: 0.7

      instruction ~p\"\"\"
      You are a helpful assistant for {{ company_name }}.
      \"\"\"

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

  Then call the agent using the generated context functions:

  ```elixir
  # Build context with instruction and user message
  context =
    [
      MyApp.ChatAgent.instruction(company_name: "Acme Corp"),
      MyApp.ChatAgent.user(message: "Hello!")
    ]
    |> MyApp.ChatAgent.context()

  # Call the agent
  {:ok, result} = MyApp.ChatAgent.call(context)
  result.output.content
  #=> "Hello! How can I help you today?"

  # For multi-turn conversations, reuse the context from the result
  new_context =
    [
      result.context,
      MyApp.ChatAgent.user(message: "What's the weather?")
    ]
    |> MyApp.ChatAgent.context()

  {:ok, result2} = MyApp.ChatAgent.call(new_context)
  ```

  ## Generated Functions

  The extension generates these functions on your agent module:

  - `context/1` - Wraps a list of messages into an `AshAgent.Context`
  - `instruction/1` - Creates a system message (validates against instruction_schema)
  - `user/1` - Creates a user message (validates against input_schema)

  ## Generated Actions

  The extension automatically generates these actions on your resource:

  - `:call` - Call the agent and return a structured response
  - `:stream` - Stream partial responses from the agent

  These actions integrate with Ash's action system, enabling actor-based
  authorization, policies, preparations, and all other Ash action features.

  ## DSL Documentation

  See `AshAgent.DSL` for complete DSL documentation.
  """

  alias AshAgent.DSL

  use Spark.Dsl.Extension,
    sections: [DSL.agent()],
    transformers: [
      AshAgent.Transformers.InjectExtensionConfig,
      AshAgent.Transformers.ValidateAgent,
      AshAgent.Transformers.GenerateContextFunctions,
      AshAgent.Transformers.AddAgentActions
    ],
    imports: [DSL]

  @doc false
  defmacro __using__(_opts) do
    quote do
      import AshAgent.Sigils, only: [sigil_p: 2]
    end
  end
end
