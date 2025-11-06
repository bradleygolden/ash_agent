defmodule AshAgent.Runtime do
  @moduledoc """
  Runtime execution engine for AshAgent.

  This module handles the execution of agent calls by:
  1. Reading agent configuration from the DSL
  2. Rendering prompt templates with provided arguments
  3. Converting TypedStruct definitions to req_llm schemas
  4. Calling ReqLLM to generate or stream responses
  5. Parsing and returning structured results
  """

  alias AshAgent.Error
  alias AshAgent.Runtime.Hooks
  alias AshAgent.Runtime.LLMClient
  alias AshAgent.Runtime.PromptRenderer
  alias AshAgent.SchemaConverter
  alias Spark.Dsl.Extension

  @doc """
  Calls an agent with the given arguments.

  Returns `{:ok, result}` where result is an instance of the agent's output TypedStruct,
  or `{:error, reason}` on failure.

  ## Examples

      # Define an agent resource
      defmodule MyApp.ChatAgent do
        use Ash.Resource,
          domain: MyApp.Domain,
          extensions: [AshAgent.Resource]

        defmodule Reply do
          use Ash.TypedStruct

          typed_struct do
            field :content, :string, enforce: true
          end
        end

        agent do
          client "anthropic:claude-3-5-sonnet"
          output Reply
          prompt "You are a helpful assistant. Reply to: {{ message }}"
        end

        input do
          argument :message, :string
        end
      end

      # Call the agent
      {:ok, reply} = AshAgent.Runtime.call(MyApp.ChatAgent, message: "Hello!")
      reply.content
      #=> "Hello! How can I assist you today?"

  """
  @spec call(module(), keyword() | map()) :: {:ok, struct()} | {:error, term()}
  def call(module, args) do
    case get_agent_config(module) do
      {:ok, config} ->
        call_with_hooks(config, module, args)

      {:error, _} = error ->
        error
    end
  end

  defp call_with_hooks(config, module, args) do
    context = Hooks.build_context(module, args)

    with {:ok, context} <- Hooks.execute(config.hooks, :before_call, context),
         {:ok, prompt} <- render_prompt(config, context.input),
         context = Hooks.with_prompt(context, prompt),
         {:ok, context} <- Hooks.execute(config.hooks, :after_render, context),
         {:ok, schema} <- build_schema(config),
         {:ok, response} <-
           LLMClient.generate_object(
             config.client,
             context.rendered_prompt,
             schema,
             config.client_opts
           ),
         {:ok, result} <- LLMClient.parse_response(config.output_type, response),
         context = Hooks.with_response(context, result),
         {:ok, context} <- Hooks.execute(config.hooks, :after_call, context) do
      {:ok, context.response}
    else
      {:error, error} = result ->
        context = Hooks.with_error(context, error)

        case Hooks.execute(config.hooks, :on_error, context) do
          {:ok, _context} -> result
          {:error, transformed_error} -> {:error, transformed_error}
        end
    end
  end

  @doc """
  Calls an agent with the given arguments, raising on error.

  Returns the result struct directly or raises an exception.
  """
  @spec call!(module(), keyword() | map()) :: struct() | no_return()
  def call!(module, args) do
    case call(module, args) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  @doc """
  Streams an agent response with the given arguments.

  Returns `{:ok, stream}` where stream yields partial results,
  or `{:error, reason}` on failure.

  Note: For structured outputs, the stream completes when the full JSON object
  is received, as complete JSON is required for parsing into the TypedStruct.

  ## Examples

      # Using the same ChatAgent from call/2 example
      {:ok, stream} = AshAgent.Runtime.stream(MyApp.ChatAgent, message: "Hello!")

      # The stream yields the complete structured result
      results = Enum.to_list(stream)
      [reply] = results
      reply.content
      #=> "Hello! How can I assist you today?"

  """
  @spec stream(module(), keyword() | map()) :: {:ok, Enumerable.t()} | {:error, term()}
  def stream(module, args) do
    case get_agent_config(module) do
      {:ok, config} ->
        stream_with_hooks(config, module, args)

      {:error, _} = error ->
        error
    end
  end

  defp stream_with_hooks(config, module, args) do
    context = Hooks.build_context(module, args)

    with {:ok, context} <- Hooks.execute(config.hooks, :before_call, context),
         {:ok, prompt} <- render_prompt(config, context.input),
         context = Hooks.with_prompt(context, prompt),
         {:ok, context} <- Hooks.execute(config.hooks, :after_render, context),
         {:ok, schema} <- build_schema(config),
         {:ok, stream_response} <-
           LLMClient.stream_object(
             config.client,
             context.rendered_prompt,
             schema,
             config.client_opts
           ) do
      stream = LLMClient.stream_to_structs(stream_response, config.output_type)

      wrapped_stream =
        Stream.map(stream, fn result ->
          context = Hooks.with_response(context, result)

          case Hooks.execute(config.hooks, :after_call, context) do
            {:ok, context} -> context.response
            {:error, _} -> result
          end
        end)

      {:ok, wrapped_stream}
    else
      {:error, error} = result ->
        context = Hooks.with_error(context, error)

        case Hooks.execute(config.hooks, :on_error, context) do
          {:ok, _context} -> result
          {:error, transformed_error} -> {:error, transformed_error}
        end
    end
  end

  @doc """
  Streams an agent response with the given arguments, raising on error.

  Returns a stream that yields partial results or raises an exception.
  """
  @spec stream!(module(), keyword() | map()) :: Enumerable.t() | no_return()
  def stream!(module, args) do
    case stream(module, args) do
      {:ok, stream} -> stream
      {:error, error} -> raise error
    end
  end

  defp get_agent_config(module) do
    {client_string, client_opts} = Extension.get_opt(module, [:agent], :client, nil, true)

    config = %{
      client: client_string,
      client_opts: client_opts,
      prompt: Extension.get_opt(module, [:agent], :prompt, nil, true),
      output_type: get_output_type(module),
      input_args: get_input_args(module),
      hooks: Extension.get_opt(module, [:agent], :hooks, nil, true)
    }

    {:ok, config}
  rescue
    e ->
      {:error,
       Error.config_error("Failed to load agent configuration", %{
         module: module,
         exception: e
       })}
  end

  defp get_output_type(module) do
    Extension.get_opt(module, [:agent], :output, nil, true)
  end

  defp get_input_args(module) do
    Extension.get_entities(module, [:agent, :input])
  end

  @spec render_prompt(map(), keyword() | map()) :: {:ok, String.t()} | {:error, String.t()}
  defp render_prompt(config, args) do
    PromptRenderer.render(config.prompt, args, config)
  end

  defp build_schema(config) do
    case config.output_type do
      nil ->
        {:error, Error.schema_error("No output type defined for agent")}

      type_module ->
        schema = SchemaConverter.to_req_llm_schema(type_module)
        {:ok, schema}
    end
  rescue
    e ->
      {:error,
       Error.schema_error("Failed to build schema", %{
         output_type: config.output_type,
         exception: e
       })}
  end
end
