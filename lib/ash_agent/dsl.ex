defmodule AshAgent.DSL do
  @moduledoc """
  DSL definitions for AshAgent extension.

  Provides the `agent` section for defining LLM agents with Zoi schema-based
  inputs/outputs, instruction templates, and automatic function generation.
  """

  @agent %Spark.Dsl.Section{
    name: :agent,
    describe: """
    Configuration for agent behavior and LLM integration.

    Defines the LLM client, instruction template, input schema, and output schema
    for the agent using Zoi validation schemas. The extension generates context
    builder functions for creating properly structured message sequences.
    """,
    examples: [
      """
      agent do
        client "anthropic:claude-sonnet-4-20250514", temperature: 0.5

        instruction ~p\"\"\"
        You are a helpful assistant for {{ company_name }}.
        Always respond in a professional tone.
        \"\"\"

        instruction_schema Zoi.object(%{
          company_name: Zoi.string()
        }, coerce: true)

        input_schema Zoi.object(%{
          message: Zoi.string()
        }, coerce: true)

        output_schema Zoi.object(%{
          content: Zoi.string()
        }, coerce: true)
      end

      # Usage with generated context functions:
      # context =
      #   [
      #     ChatAgent.instruction(company_name: "Acme"),
      #     ChatAgent.user(message: "Hello!")
      #   ]
      #   |> ChatAgent.context()
      #
      # ChatAgent.call(context)
      """
    ],
    schema: [
      provider: [
        type: :atom,
        default: :req_llm,
        doc: """
        LLM provider implementation.

        Can be an atom preset (`:req_llm`, `:mock`) or a custom module
        implementing the `AshAgent.Provider` behavior.

        Examples:
          provider :req_llm          # Default, uses ReqLLM library
          provider :mock             # Mock provider for testing
          provider MyApp.CustomProvider  # Custom provider module
        """
      ],
      client: [
        type: {:custom, __MODULE__, :validate_client_config, []},
        required: true,
        doc: """
        LLM provider and model configuration with optional parameters.

        Syntax:
          client "provider:model"
          client "provider:model", temperature: 0.7, max_tokens: 1000

        The first argument is the provider:model string (required).
        Additional keyword arguments are passed through to ReqLLM as options.
        Common options: :temperature, :max_tokens
        """
      ],
      instruction: [
        type: {:or, [:string, {:struct, Solid.Template}]},
        required: true,
        doc: """
        System instruction template for the agent.

        This defines the system prompt that sets the agent's behavior and context.
        Rendered with arguments from `instruction_schema` at call time.

        Use ~p sigil for compile-time validation:

            instruction ~p\"\"\"
            You are a helpful assistant for {{ company_name }}.
            \"\"\"

        When calling the agent, build context with generated functions:

            context =
              [
                ChatAgent.instruction(company_name: "Acme"),
                ChatAgent.user(message: "Hello!")
              ]
              |> ChatAgent.context()

            ChatAgent.call(context)
        """
      ],
      instruction_schema: [
        type: :any,
        required: false,
        doc: """
        Zoi schema for instruction template arguments.

        Validates and coerces arguments passed to the generated `instruction/1` function.

        Example:

            instruction_schema Zoi.object(%{
              company_name: Zoi.string(),
              persona: Zoi.string() |> Zoi.optional() |> Zoi.default("helpful assistant")
            }, coerce: true)
        """
      ],
      input_schema: [
        type: :any,
        required: true,
        doc: """
        Zoi schema for user message content validation and coercion.

        Validates arguments passed to the generated `user/1` function.

        Examples:
          input_schema Zoi.object(%{message: Zoi.string()}, coerce: true)
          input_schema Zoi.object(%{
            message: Zoi.string(),
            context: Zoi.map() |> Zoi.optional() |> Zoi.default(%{})
          }, coerce: true)
        """
      ],
      output_schema: [
        type: :any,
        required: true,
        doc: """
        Zoi schema for output validation and coercion.

        Use Zoi.object/2 for structured outputs, or primitive schemas like
        Zoi.string() for simple outputs. Use |> Zoi.to_struct(Module) to
        convert validated output to a struct.

        Examples:
          output_schema Zoi.object(%{content: Zoi.string()}, coerce: true)
          output_schema Zoi.object(%{content: Zoi.string()}, coerce: true) |> Zoi.to_struct(Reply)
          output_schema Zoi.string()
        """
      ],
      hooks: [
        type: :atom,
        required: false,
        doc: """
        Module implementing the AshAgent.Runtime.Hooks behaviour.

        Hooks allow you to inject custom behavior at key points in the agent execution lifecycle:
        - before_call: Called before rendering prompt or calling LLM
        - after_render: Called after prompt rendering, before LLM call
        - after_call: Called after successful LLM response
        - on_error: Called when any error occurs

        See `AshAgent.Runtime.Hooks` for more details.
        """
      ],
      token_budget: [
        type: :pos_integer,
        required: false,
        doc: """
        Maximum number of tokens allowed for this agent execution.

        When set, the agent will track cumulative token usage and enforce
        the budget according to the configured budget_strategy.
        """
      ],
      budget_strategy: [
        type: {:in, [:halt, :warn]},
        default: :warn,
        doc: """
        Strategy for handling token budget limits.

        - :halt - Stop execution and return budget error when limit exceeded
        - :warn - Emit telemetry warning at threshold (default 80%) but continue

        Defaults to :warn for backward compatibility.
        """
      ]
    ]
  }

  @doc false
  def validate_client_config(client) when is_binary(client), do: {:ok, {client, []}}
  def validate_client_config(client) when is_atom(client), do: {:ok, {client, []}}

  def validate_client_config([client | opts]) when is_list(opts) do
    cond do
      is_binary(client) -> {:ok, {client, opts}}
      is_atom(client) -> {:ok, {client, opts}}
      true -> error_invalid_client([client | opts])
    end
  end

  def validate_client_config(value), do: error_invalid_client(value)

  defp error_invalid_client(value) do
    {:error,
     "client must be a string or atom optionally followed by keyword options, got: #{inspect(value)}"}
  end

  @doc """
  Defines the LLM client with optional parameters.

  ## Examples

      client "anthropic:claude-3-5-sonnet"
      client "anthropic:claude-3-5-sonnet", temperature: 0.7, max_tokens: 1000
  """
  defmacro client(client_string, opts \\ []) do
    quote do
      client([unquote(client_string) | unquote(opts)])
    end
  end

  def agent, do: @agent

  def template_agent do
    %{@agent | schema: template_schema()}
  end

  defp template_schema do
    @agent.schema
    |> Keyword.delete(:client)
    |> Keyword.delete(:provider)
    |> Keyword.update!(:instruction, fn opts -> Keyword.put(opts, :required, false) end)
    |> Keyword.update!(:input_schema, fn opts -> Keyword.put(opts, :required, false) end)
  end
end
