defmodule AshAgent.Transformers.GenerateContextFunctions do
  @moduledoc """
  Generates context builder functions on agent modules.

  This transformer creates three functions on each agent module:

  - `context/1` - Wraps a list of messages into an `AshAgent.Context`
  - `instruction/1` - Creates a system message, validating against instruction_schema
  - `user/1` - Creates a user message, validating against input_schema

  These functions enable the list-based context builder pattern:

      context =
        [
          ChatAgent.instruction(company_name: "Acme"),
          ChatAgent.user(message: "Hello!")
        ]
        |> ChatAgent.context()

      ChatAgent.call(context)
  """

  use Spark.Dsl.Transformer

  alias AshAgent.Runtime.PromptRenderer
  alias Spark.Dsl.Transformer

  @impl true
  def transform(dsl_state) do
    instruction_template = Transformer.get_option(dsl_state, [:agent], :instruction)
    instruction_schema = Transformer.get_option(dsl_state, [:agent], :instruction_schema)
    input_schema = Transformer.get_option(dsl_state, [:agent], :input_schema)

    instruction_fn = build_instruction_function(instruction_template, instruction_schema)

    code =
      quote do
        @doc """
        Creates a context from a list of messages.

        Accepts `AshAgent.Message` structs or other `AshAgent.Context` structs
        (for multi-turn conversations).

        ## Examples

            context =
              [
                __MODULE__.instruction(company_name: "Acme"),
                __MODULE__.user(message: "Hello!")
              ]
              |> __MODULE__.context()
        """
        def context(messages) when is_list(messages) do
          AshAgent.Context.new(messages)
        end

        unquote(instruction_fn)

        @doc """
        Creates a user message.

        Validates arguments against the input_schema and returns an `AshAgent.Message`.
        """
        def user(args) when is_list(args), do: user(Map.new(args))

        def user(args) when is_map(args) do
          input_schema = unquote(Macro.escape(input_schema))

          validated_args =
            if input_schema do
              case Zoi.parse(input_schema, args) do
                {:ok, validated} -> validated
                {:error, errors} -> raise ArgumentError, "Invalid user args: #{inspect(errors)}"
              end
            else
              args
            end

          AshAgent.Message.user(validated_args)
        end
      end

    dsl_state = Transformer.eval(dsl_state, [], code)
    {:ok, dsl_state}
  end

  defp build_instruction_function(nil, _instruction_schema) do
    quote do
      @doc """
      Creates an empty system instruction message.

      This agent has no instruction template configured.
      """
      def instruction(_args \\ []) do
        AshAgent.Message.system("")
      end
    end
  end

  defp build_instruction_function(instruction_template, instruction_schema) do
    quote do
      @doc """
      Creates a system instruction message.

      Validates arguments against the instruction_schema (if configured),
      renders the instruction template, and returns an `AshAgent.Message`.
      """
      def instruction(args \\ [])

      def instruction(args) when is_list(args), do: instruction(Map.new(args))

      def instruction(args) when is_map(args) do
        instruction_schema = unquote(Macro.escape(instruction_schema))

        validated_args =
          if instruction_schema do
            case Zoi.parse(instruction_schema, args) do
              {:ok, validated} ->
                validated

              {:error, errors} ->
                raise ArgumentError, "Invalid instruction args: #{inspect(errors)}"
            end
          else
            args
          end

        content =
          case unquote(__MODULE__).render_template(
                 unquote(Macro.escape(instruction_template)),
                 validated_args
               ) do
            {:ok, rendered} ->
              rendered

            {:error, reason} ->
              raise ArgumentError, "Failed to render instruction: #{inspect(reason)}"
          end

        AshAgent.Message.system(content)
      end
    end
  end

  @doc false
  def render_template(template, args) do
    PromptRenderer.render(template, args, %{})
  end

  @impl true
  def after?(AshAgent.Transformers.ValidateAgent), do: true
  def after?(_), do: false
end
