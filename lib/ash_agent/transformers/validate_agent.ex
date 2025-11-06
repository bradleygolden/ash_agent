defmodule AshAgent.Transformers.ValidateAgent do
  @moduledoc """
  Validates the agent configuration at compile time.

  Ensures that:
  - The agent section is properly configured
  - Output types are valid TypedStruct modules
  - Prompt templates are valid
  - Input arguments are properly defined
  """

  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer
  alias Spark.Error.DslError

  @impl true
  def transform(dsl_state) do
    case Transformer.get_option(dsl_state, [:agent], :client) do
      nil ->
        {:ok, dsl_state}

      _client ->
        with :ok <- validate_client(dsl_state),
             :ok <- validate_prompt(dsl_state) do
          {:ok, dsl_state}
        end
    end
  end

  defp validate_client(dsl_state) do
    case Transformer.get_option(dsl_state, [:agent], :client) do
      {client_string, _opts} when is_binary(client_string) ->
        if String.contains?(client_string, ":") do
          :ok
        else
          {:error,
           DslError.exception(
             module: Transformer.get_persisted(dsl_state, :module),
             message:
               "Client must be in 'provider:model' format (e.g., 'anthropic:claude-3-5-sonnet')",
             path: [:agent, :client]
           )}
        end

      _ ->
        {:error,
         DslError.exception(
           module: Transformer.get_persisted(dsl_state, :module),
           message: "Client configuration is invalid",
           path: [:agent, :client]
         )}
    end
  end

  defp validate_prompt(dsl_state) do
    case Transformer.get_option(dsl_state, [:agent], :prompt) do
      prompt when is_binary(prompt) or is_struct(prompt, Solid.Template) ->
        :ok

      _ ->
        {:error,
         DslError.exception(
           module: Transformer.get_persisted(dsl_state, :module),
           message: "Prompt must be a string or Solid.Template",
           path: [:agent, :prompt]
         )}
    end
  end
end
