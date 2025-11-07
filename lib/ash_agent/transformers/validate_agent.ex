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

  alias AshAgent.ProviderRegistry
  alias Spark.Dsl.Transformer
  alias Spark.Error.DslError

  @impl true
  def transform(dsl_state) do
    case Transformer.get_option(dsl_state, [:agent], :client) do
      nil ->
        {:ok, dsl_state}

      _client ->
        with :ok <- validate_client(dsl_state),
             :ok <- validate_prompt(dsl_state),
             :ok <- validate_provider_capabilities(dsl_state),
             :ok <- ensure_baml_client_module(dsl_state) do
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

      {client_atom, _opts} when is_atom(client_atom) ->
        :ok

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
    prompt = Transformer.get_option(dsl_state, [:agent], :prompt)
    provider = Transformer.get_option(dsl_state, [:agent], :provider, :req_llm)
    features = ProviderRegistry.features(provider)

    cond do
      is_binary(prompt) or is_struct(prompt, Solid.Template) ->
        :ok

      prompt in [nil, ""] and :prompt_optional in features ->
        :ok

      true ->
        {:error,
         DslError.exception(
           module: Transformer.get_persisted(dsl_state, :module),
           message: "Prompt must be provided unless the provider declares :prompt_optional",
           path: [:agent, :prompt]
         )}
    end
  end

  defp validate_provider_capabilities(dsl_state) do
    provider = Transformer.get_option(dsl_state, [:agent], :provider, :req_llm)
    features = ProviderRegistry.features(provider)

    tools = Transformer.get_entities(dsl_state, [:tools]) || []

    cond do
      tools != [] and :tool_calling not in features ->
        {:error,
         DslError.exception(
           module: Transformer.get_persisted(dsl_state, :module),
           message:
             "Provider #{inspect(provider)} does not support tool calling. Remove the `tools` section or choose a provider that declares :tool_calling.",
           path: [:tools]
         )}

      true ->
        :ok
    end
  end

  defp ensure_baml_client_module(dsl_state) do
    provider = Transformer.get_option(dsl_state, [:agent], :provider, :req_llm)

    if provider == :baml do
      case Transformer.get_option(dsl_state, [:agent], :client) do
        {client, _opts} -> ensure_baml_client_module_for_value(client, dsl_state)
        _ -> :ok
      end
    else
      :ok
    end
  end

  defp ensure_baml_client_module_for_value(client, _dsl_state) when is_binary(client), do: :ok

  defp ensure_baml_client_module_for_value(client, dsl_state) when is_atom(client) do
    if Code.ensure_loaded?(client) do
      :ok
    else
      ensure_baml_client_from_config(client, dsl_state)
    end
  end

  defp ensure_baml_client_module_for_value(_client, _dsl_state), do: :ok

  defp ensure_baml_client_from_config(identifier, dsl_state) do
    case Code.ensure_loaded(AshBaml.ClientBuilder) do
      {:module, builder} ->
        case builder.ensure_configured_client_module(identifier) do
          {:ok, _module} ->
            :ok

          {:error, reason} ->
            {:error,
             DslError.exception(
               module: Transformer.get_persisted(dsl_state, :module),
               message: reason,
               path: [:agent, :client]
             )}
        end

      {:error, _} ->
        :ok
    end
  end
end
