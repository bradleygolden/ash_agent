defmodule AshAgent.IntegrationCase do
  @moduledoc """
  ExUnit case template for integration tests.

  Both `backend` and `provider` options are optional. Use what makes sense for your app.

  ## Usage

      # With backend and provider (e.g., ash_agent)
      defmodule AshAgent.Integration.ReqLLM.OpenAI.MetadataTest do
        use AshAgent.IntegrationCase, backend: :req_llm, provider: :openai

        test "extracts usage metadata" do
          # ...
        end
      end

      # Provider only (e.g., ash_baml where BAML is the backend)
      defmodule AshAgent.Integration.Ollama.StreamingTest do
        use AshAgent.IntegrationCase, provider: :ollama

        test "streams responses" do
          # ...
        end
      end

  ## Running Tests

      mix test.integration                              # All integration tests
      mix test.integration --only backend:req_llm       # All ReqLLM tests
      mix test.integration --only provider:openai       # All OpenAI tests
      mix test.integration --only backend:baml --only provider:anthropic
  """

  use ExUnit.CaseTemplate

  @providers %{
    openai: {"OPENAI_API_KEY", "OpenAI"},
    anthropic: {"ANTHROPIC_API_KEY", "Anthropic"},
    openrouter: {"OPENROUTER_API_KEY", "OpenRouter"},
    ollama: {nil, "Ollama (local)"}
  }

  @backends [:req_llm, :baml]

  using options do
    backend = Keyword.get(options, :backend)
    provider = Keyword.get(options, :provider)

    quote do
      use ExUnit.Case, async: false

      @moduletag :integration
      if unquote(backend), do: @moduletag(backend: unquote(backend))
      if unquote(provider), do: @moduletag(provider: unquote(provider))
    end
  end

  setup context do
    if backend = context[:backend] do
      validate_backend!(backend)
    end

    if provider = context[:provider] do
      validate_provider_key!(provider)
    end

    :ok
  end

  defp validate_backend!(backend) do
    unless backend in @backends do
      raise """

      ══════════════════════════════════════════════════════════════
      UNKNOWN BACKEND: #{inspect(backend)}
      ══════════════════════════════════════════════════════════════

      Known backends: #{Enum.join(@backends, ", ")}
      ══════════════════════════════════════════════════════════════
      """
    end
  end

  defp validate_provider_key!(provider) do
    case Map.get(@providers, provider) do
      nil ->
        raise """

        ══════════════════════════════════════════════════════════════
        UNKNOWN PROVIDER: #{inspect(provider)}
        ══════════════════════════════════════════════════════════════

        Known providers: #{@providers |> Map.keys() |> Enum.join(", ")}

        To add a new provider, update @providers in:
          test/support/integration_case.ex
        ══════════════════════════════════════════════════════════════
        """

      {nil, _name} ->
        :ok

      {env_var, provider_name} ->
        unless System.get_env(env_var) do
          raise """

          ══════════════════════════════════════════════════════════════
          MISSING API KEY: #{env_var}
          ══════════════════════════════════════════════════════════════

          This test requires a #{provider_name} API key.

          To run:
              export #{env_var}="your-api-key"
              mix test.integration --only provider:#{provider}

          To skip:
              mix test.integration --exclude provider:#{provider}

          ══════════════════════════════════════════════════════════════
          """
        end
    end
  end
end
