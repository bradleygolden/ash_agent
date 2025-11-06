defmodule AshAgent.Resource do
  @moduledoc """
  The AshAgent resource extension.

  This extension allows you to define LLM agents as Ash resources with type-safe
  inputs/outputs, prompt templates, and automatic action generation.

  ## Usage

  Define an agent resource:

  ```elixir
  defmodule MyApp.ChatAgent do
    use Ash.Resource,
      domain: MyApp.Domain,
      extensions: [AshAgent.Resource]

    defmodule Reply do
      use Ash.TypedStruct

      typed_struct do
        field :content, String.t(), enforce: true
      end
    end

    agent do
      client "anthropic:claude-3-5-sonnet", temperature: 0.7, max_tokens: 1000

      input do
        argument :message, :string, allow_nil?: false
      end

      output Reply

      prompt ~p\"\"\"
      You are a helpful assistant.

      {{ output_format }}

      User: {{ message }}
      \"\"\"
    end

    code_interface do
      define :call, args: [:message]
      define :stream, args: [:message]
    end
  end
  ```

  Then call the agent:

  ```elixir
  # Via code interface (positional arguments)
  {:ok, reply} = MyApp.ChatAgent.call("Hello!")

  # Or keyword arguments
  {:ok, reply} = MyApp.ChatAgent.call(message: "Hello!")

  # Or via Ash.ActionInput for advanced usage (actor, tenant, etc.)
  MyApp.ChatAgent
  |> Ash.ActionInput.for_action(:call, %{message: "Hello!"}, actor: current_user)
  |> Ash.run_action()
  ```

  You can also define code interfaces in your domain:

  ```elixir
  defmodule MyApp.Domain do
    use Ash.Domain

    resources do
      resource MyApp.ChatAgent do
        define :call, args: [:message]
        define :stream, args: [:message]
      end
    end
  end
  ```

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
    sections: [DSL.agent(), DSL.Tools.tools()],
    transformers: [
      AshAgent.Transformers.ValidateAgent,
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
