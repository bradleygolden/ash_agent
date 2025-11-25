defmodule AshAgent.ExtensionTest do
  use ExUnit.Case, async: true

  alias AshAgent.Extension
  alias AshAgent.Error
  alias AshAgent.Test.TestAgents

  describe "get_config/1" do
    test "returns {:ok, config} for valid agent module" do
      assert {:ok, config} = Extension.get_config(TestAgents.MinimalAgent)
      assert is_map(config)
      assert config.client == "anthropic:claude-3-5-sonnet"
    end

    test "returns {:error, _} for invalid module" do
      assert {:error, %Error{type: :config_error}} = Extension.get_config(NonExistentModule)
    end
  end

  describe "apply_runtime_overrides/2" do
    setup do
      {:ok, config} = Extension.get_config(TestAgents.MinimalAgent)
      {:ok, config: config}
    end

    test "returns {:ok, config} with no overrides", %{config: config} do
      assert {:ok, new_config} = Extension.apply_runtime_overrides(config, [])
      assert new_config.provider == config.provider
    end

    test "applies provider override", %{config: config} do
      assert {:ok, new_config} = Extension.apply_runtime_overrides(config, provider: :mock)
      assert new_config.provider == :mock
      # Client opts reset when provider changes
      assert new_config.client_opts == []
    end

    test "applies client override as string", %{config: config} do
      assert {:ok, new_config} =
               Extension.apply_runtime_overrides(config, client: "openai:gpt-4")

      assert new_config.client == "openai:gpt-4"
    end

    test "applies client override as tuple with opts", %{config: config} do
      assert {:ok, new_config} =
               Extension.apply_runtime_overrides(config,
                 client: {"openai:gpt-4", [temperature: 0.9]}
               )

      assert new_config.client == "openai:gpt-4"
      assert new_config.client_opts == [temperature: 0.9]
    end

    test "merges client_opts", %{config: _config} do
      {:ok, config_with_opts} = Extension.get_config(TestAgents.AgentWithClientOpts)

      assert {:ok, new_config} =
               Extension.apply_runtime_overrides(config_with_opts, client_opts: [top_p: 0.5])

      assert :temperature in Keyword.keys(new_config.client_opts)
      assert :top_p in Keyword.keys(new_config.client_opts)
    end

    test "applies profile override", %{config: config} do
      assert {:ok, new_config} = Extension.apply_runtime_overrides(config, profile: :production)
      assert new_config.profile == :production
    end

    test "accepts map as runtime_opts", %{config: config} do
      assert {:ok, new_config} = Extension.apply_runtime_overrides(config, %{provider: :mock})
      assert new_config.provider == :mock
    end
  end

  describe "validate_provider_capabilities/2" do
    test "returns :ok for valid call capability" do
      config = %{provider: :req_llm, tools: []}
      assert :ok = Extension.validate_provider_capabilities(config, :call)
    end

    test "returns :ok for valid stream capability" do
      config = %{provider: :req_llm, tools: []}
      assert :ok = Extension.validate_provider_capabilities(config, :stream)
    end

    test "returns error when tools requested but provider doesn't support" do
      # Mock provider supports tool_calling, so we'd need a provider that doesn't
      # For now, test with a provider that has empty features
      config = %{provider: :unknown_provider, tools: [%{name: "test"}]}

      assert {:error, %Error{type: :validation_error}} =
               Extension.validate_provider_capabilities(config, :call)
    end
  end

  describe "render_prompt/3" do
    test "renders simple template with args" do
      config = %{output_type: nil}

      assert {:ok, rendered} =
               Extension.render_prompt("Hello {{ name }}", %{name: "World"}, config)

      assert rendered == "Hello World"
    end

    test "renders template with output_format variable" do
      config = %{output_type: nil}

      assert {:ok, rendered} =
               Extension.render_prompt("Format: {{ output_format }}", %{}, config)

      assert rendered =~ "JSON"
    end

    test "returns error for invalid template syntax" do
      config = %{output_type: nil}

      assert {:error, %Error{type: :prompt_error}} =
               Extension.render_prompt("Hello {{ name", %{name: "World"}, config)
    end
  end

  describe "build_schema/1" do
    test "returns {:ok, schema} for module with output type" do
      {:ok, config} = Extension.get_config(TestAgents.MinimalAgent)

      assert {:ok, schema} = Extension.build_schema(config)
      assert is_list(schema)
    end

    test "returns {:ok, nil} for :string output type" do
      config = %{provider: :req_llm, output_type: :string}

      assert {:ok, nil} = Extension.build_schema(config)
    end

    test "returns error when output type is nil" do
      config = %{provider: :req_llm, output_type: nil}

      assert {:error, %Error{type: :schema_error}} = Extension.build_schema(config)
    end
  end

  describe "parse_response/2" do
    test "parses map response to struct" do
      response = %{"message" => "Hello"}

      assert {:ok, struct} = Extension.parse_response(TestAgents.SimpleOutput, response)
      assert struct.message == "Hello"
    end

    test "handles map response for complex typed struct" do
      response = %{"title" => "Test", "description" => "Desc", "score" => 0.5, "tags" => ["a"]}

      assert {:ok, struct} = Extension.parse_response(TestAgents.ComplexOutput, response)
      assert struct.title == "Test"
      assert struct.description == "Desc"
      assert struct.score == 0.5
    end
  end

  describe "telemetry_metadata/3" do
    test "builds metadata map with all fields" do
      {:ok, config} = Extension.get_config(TestAgents.MinimalAgent)

      metadata = Extension.telemetry_metadata(config, TestAgents.MinimalAgent, :call)

      assert metadata.agent == TestAgents.MinimalAgent
      assert metadata.client == "anthropic:claude-3-5-sonnet"
      assert metadata.provider == :req_llm
      assert metadata.type == :call
      assert metadata.output_type == TestAgents.SimpleOutput
    end

    test "includes profile when set" do
      {:ok, config} = Extension.get_config(TestAgents.MinimalAgent)
      {:ok, config_with_profile} = Extension.apply_runtime_overrides(config, profile: :test)

      metadata = Extension.telemetry_metadata(config_with_profile, TestAgents.MinimalAgent, :call)

      assert metadata.profile == :test
    end
  end

  describe "error construction functions" do
    test "config_error/2 creates config error" do
      error = Extension.config_error("Test error", %{key: :value})

      assert %Error{} = error
      assert error.type == :config_error
      assert error.message == "Test error"
      assert error.details == %{key: :value}
    end

    test "llm_error/2 creates LLM error" do
      error = Extension.llm_error("API failed", %{status: 500})

      assert error.type == :llm_error
      assert error.details == %{status: 500}
    end

    test "validation_error/2 creates validation error" do
      error = Extension.validation_error("Invalid input")

      assert error.type == :validation_error
    end

    test "budget_error/2 creates budget error" do
      error = Extension.budget_error("Over limit", %{used: 10000, limit: 5000})

      assert error.type == :budget_error
      assert error.details.used == 10000
    end
  end

  describe "resolve_provider/1" do
    test "resolves :req_llm to provider module" do
      assert {:ok, AshAgent.Providers.ReqLLM} = Extension.resolve_provider(:req_llm)
    end

    test "resolves :mock to provider module" do
      assert {:ok, AshAgent.Providers.Mock} = Extension.resolve_provider(:mock)
    end

    test "returns error for unknown provider" do
      assert {:error, _} = Extension.resolve_provider(:unknown)
    end
  end

  describe "check_token_limit/6" do
    test "returns :ok when under budget" do
      assert :ok =
               Extension.check_token_limit(
                 500,
                 "anthropic:claude-3-5-sonnet",
                 nil,
                 nil,
                 1000,
                 :halt
               )
    end

    test "returns :ok when no budget set" do
      assert :ok =
               Extension.check_token_limit(
                 500,
                 "anthropic:claude-3-5-sonnet",
                 nil,
                 nil,
                 nil,
                 :warn
               )
    end
  end
end
