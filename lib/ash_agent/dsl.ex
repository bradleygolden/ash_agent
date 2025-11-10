defmodule AshAgent.DSL do
  @moduledoc """
  DSL definitions for AshAgent extension.

  Provides the `agent` section for defining LLM agents with type-safe inputs/outputs,
  prompt templates, and automatic function generation.
  """

  defmodule Argument do
    @moduledoc false
    defstruct [:name, :type, :allow_nil?, :default, :doc, :__spark_metadata__]
  end

  @argument %Spark.Dsl.Entity{
    name: :argument,
    describe: "Defines an input argument for the agent",
    examples: [
      "argument :message, :string, allow_nil?: false",
      "argument :context, :map, default: %{}"
    ],
    target: AshAgent.DSL.Argument,
    args: [:name, :type],
    schema: [
      name: [
        type: :atom,
        required: true,
        doc: "The name of the argument"
      ],
      type: [
        type: {:in, [:string, :integer, :float, :boolean, :map, :list, {:array, :any}]},
        required: true,
        doc: "The type of the argument"
      ],
      allow_nil?: [
        type: :boolean,
        default: true,
        doc: "Whether the argument can be nil"
      ],
      default: [
        type: :any,
        doc: "Default value for the argument"
      ],
      doc: [
        type: :string,
        doc: "Documentation for the argument"
      ]
    ]
  }

  @input %Spark.Dsl.Section{
    name: :input,
    describe: "Defines the input arguments accepted by the agent",
    examples: [
      """
      input do
        argument :message, :string, allow_nil?: false
        argument :context, :map, default: %{}
      end
      """
    ],
    entities: [@argument]
  }

  @agent %Spark.Dsl.Section{
    name: :agent,
    describe: """
    Configuration for agent behavior and LLM integration.

    Defines the LLM client, prompt template, input arguments, and output types
    for the agent.
    """,
    examples: [
      """
      agent do
        client "anthropic:claude-3-5-sonnet", temperature: 0.5, max_tokens: 100

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
      output: [
        type: :atom,
        required: true,
        doc: "Ash.TypedStruct module to use as the output type"
      ],
      prompt: [
        type: {:or, [:string, {:struct, Solid.Template}]},
        required: false,
        doc: "Prompt template using Liquid syntax. Use ~p sigil for compile-time validation."
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
    ],
    sections: [@input]
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
  def input, do: @input
end
