defmodule AshAgent.ProviderRegistryTest do
  use ExUnit.Case, async: false

  alias AshAgent.ProviderRegistry
  alias AshAgent.Error

  describe "resolve/1 with built-in provider keys" do
    test "resolves :req_llm to ReqLLM provider" do
      assert {:ok, AshAgent.Providers.ReqLLM} = ProviderRegistry.resolve(:req_llm)
    end

    test "resolves :mock to Mock provider" do
      assert {:ok, AshAgent.Providers.Mock} = ProviderRegistry.resolve(:mock)
    end

    test "resolves :baml to Baml provider" do
      assert {:ok, AshAgent.Providers.Baml} = ProviderRegistry.resolve(:baml)
    end
  end

  describe "resolve/1 with module references" do
    test "resolves loaded module directly" do
      assert {:ok, AshAgent.Providers.Mock} = ProviderRegistry.resolve(AshAgent.Providers.Mock)
    end

    test "returns error for non-existent module" do
      result = ProviderRegistry.resolve(NonExistentModule)

      assert {:error, %Error{type: :config_error}} = result
      assert {:error, %Error{message: message}} = result
      assert message =~ "could not be resolved"
    end
  end

  describe "resolve/1 with unknown keys" do
    test "returns error for unknown provider key that is not a valid module" do
      # Because :unknown_provider is not in @default_provider_keys, it's treated
      # as a potential module name and Code.ensure_loaded? fails
      result = ProviderRegistry.resolve(:unknown_provider)

      assert {:error, %Error{type: :config_error}} = result
      assert {:error, %Error{message: message}} = result
      assert message =~ "could not be resolved"
    end
  end

  describe "resolve/1 with invalid input" do
    test "returns error for non-atom input" do
      result = ProviderRegistry.resolve("string_provider")

      assert {:error, %Error{type: :config_error}} = result
      assert {:error, %Error{message: message}} = result
      assert message =~ "Invalid provider specification"
    end

    test "returns error for integer input" do
      result = ProviderRegistry.resolve(123)

      assert {:error, %Error{type: :config_error}} = result
    end

    test "returns error for list input" do
      result = ProviderRegistry.resolve([:some, :list])

      assert {:error, %Error{type: :config_error}} = result
    end

    test "returns error for map input" do
      result = ProviderRegistry.resolve(%{provider: :mock})

      assert {:error, %Error{type: :config_error}} = result
    end
  end

  describe "register/2" do
    setup do
      # The registry is already started via the application
      :ok
    end

    test "returns :ok when registering" do
      unique_key = :"test_provider_#{System.unique_integer([:positive])}"

      result = ProviderRegistry.register(unique_key, AshAgent.Providers.Mock)

      assert result == :ok
    end

    test "can register multiple providers" do
      for i <- 1..5 do
        key = :"batch_provider_#{System.unique_integer([:positive])}_#{i}"
        assert :ok = ProviderRegistry.register(key, AshAgent.Providers.Mock)
      end
    end
  end

  describe "features/1" do
    test "returns features for :mock provider" do
      features = ProviderRegistry.features(:mock)

      assert is_list(features)
      assert :sync_call in features
      assert :streaming in features
    end

    test "returns features for :req_llm provider" do
      features = ProviderRegistry.features(:req_llm)

      assert is_list(features)
      assert :sync_call in features
      assert :streaming in features
      assert :structured_output in features
      assert :tool_calling in features
      assert :auto_retry in features
    end

    test "returns features for :baml provider" do
      features = ProviderRegistry.features(:baml)

      assert is_list(features)
      assert :sync_call in features
      assert :streaming in features
      assert :structured_output in features
      assert :tool_calling in features
      assert :prompt_optional in features
      assert :schema_optional in features
    end

    test "returns empty list for unknown provider" do
      features = ProviderRegistry.features(:definitely_unknown_provider)

      assert features == []
    end

    test "returns features for module with introspect/0" do
      features = ProviderRegistry.features(AshAgent.Providers.Mock)

      assert is_list(features)
      assert :sync_call in features
      assert :streaming in features
      assert :configurable_responses in features
      assert :tool_calling in features
    end

    test "returns default features for module without introspect when key matches" do
      # When resolving by module, it falls back to default features if available
      features = ProviderRegistry.features(AshAgent.Providers.ReqLLM)

      assert is_list(features)
      assert :sync_call in features
    end
  end

  describe "GenServer behaviour" do
    test "registry is started as part of the application" do
      assert Process.whereis(ProviderRegistry) != nil
    end

    test "registry survives multiple resolve calls" do
      for _ <- 1..10 do
        assert {:ok, _} = ProviderRegistry.resolve(:mock)
      end
    end

    test "registry survives multiple register calls" do
      for i <- 1..5 do
        key = :"survival_test_provider_#{System.unique_integer([:positive])}_#{i}"
        assert :ok = ProviderRegistry.register(key, AshAgent.Providers.Mock)
      end
    end
  end

  describe "default providers" do
    test "all default providers are resolvable" do
      for key <- [:req_llm, :mock, :baml] do
        assert {:ok, module} = ProviderRegistry.resolve(key)
        assert is_atom(module)
      end
    end

    test "all default providers have features defined" do
      for key <- [:req_llm, :mock, :baml] do
        features = ProviderRegistry.features(key)
        assert is_list(features)
        assert length(features) > 0
      end
    end
  end
end
