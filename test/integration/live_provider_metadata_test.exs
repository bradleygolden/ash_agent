defmodule AshAgent.Integration.LiveProviderMetadataTest do
  @moduledoc false
  use ExUnit.Case, async: false

  alias AshAgent.{Metadata, Runtime}

  @moduletag :integration

  setup do
    original_opts = Application.get_env(:ash_agent, :req_llm_options, [])
    Application.put_env(:ash_agent, :req_llm_options, [])

    on_exit(fn ->
      Application.put_env(:ash_agent, :req_llm_options, original_opts)
    end)

    :ok
  end

  defmodule TestDomain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      allow_unregistered? true
    end
  end

  describe "OpenAI metadata extraction" do
    @moduletag :openai

    defmodule OpenAITestAgent do
      @moduledoc false
      use Ash.Resource,
        domain: AshAgent.Integration.LiveProviderMetadataTest.TestDomain,
        extensions: [AshAgent.Resource]

      import AshAgent.Sigils

      resource do
        require_primary_key? false
      end

      agent do
        client("openai:gpt-5-mini", temperature: 0.0)

        input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
        output_schema(Zoi.object(%{response: Zoi.string()}, coerce: true))

        instruction(~p"""
        Reply with JSON matching the output format exactly.
        {{ ctx.output_format }}
        Message: {{ message }}
        """)
      end
    end

    test "extracts usage from OpenAI response" do
      {:ok, result} = Runtime.call(OpenAITestAgent, %{message: "say hi"})

      assert is_map(result.usage)
      assert result.usage[:input_tokens] > 0
      assert result.usage[:output_tokens] > 0
    end

    test "extracts model identifier from OpenAI" do
      {:ok, result} = Runtime.call(OpenAITestAgent, %{message: "say hi"})

      assert is_binary(result.model)
      assert result.model =~ "gpt-5"
    end

    test "OpenAI metadata is JSON-serializable" do
      {:ok, result} = Runtime.call(OpenAITestAgent, %{message: "say hi"})

      state = %{
        output: result.output,
        usage: result.usage,
        model: result.model,
        metadata: Map.from_struct(result.metadata)
      }

      assert {:ok, _json} = Jason.encode(state)
    end

    test "OpenAI result has Metadata struct" do
      {:ok, result} = Runtime.call(OpenAITestAgent, %{message: "say hi"})

      assert %Metadata{} = result.metadata
      assert result.metadata.provider == :req_llm
    end
  end

  describe "Anthropic metadata extraction" do
    @moduletag :anthropic

    defmodule AnthropicTestAgent do
      @moduledoc false
      use Ash.Resource,
        domain: AshAgent.Integration.LiveProviderMetadataTest.TestDomain,
        extensions: [AshAgent.Resource]

      import AshAgent.Sigils

      resource do
        require_primary_key? false
      end

      agent do
        client("anthropic:claude-sonnet-4-5-20250929", temperature: 0.0, max_tokens: 100)

        input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
        output_schema(Zoi.object(%{response: Zoi.string()}, coerce: true))

        instruction(~p"""
        Reply with JSON matching the output format exactly.
        {{ ctx.output_format }}
        Message: {{ message }}
        """)
      end
    end

    test "extracts usage from Anthropic response" do
      {:ok, result} = Runtime.call(AnthropicTestAgent, %{message: "say hi"})

      assert is_map(result.usage)
      assert result.usage[:input_tokens] > 0
      assert result.usage[:output_tokens] > 0
    end

    test "extracts model identifier from Anthropic" do
      {:ok, result} = Runtime.call(AnthropicTestAgent, %{message: "say hi"})

      assert is_binary(result.model)
      assert result.model =~ "claude"
    end

    test "Anthropic result has Metadata struct with cached_tokens field" do
      {:ok, result} = Runtime.call(AnthropicTestAgent, %{message: "say hi"})

      assert %Metadata{} = result.metadata
      assert Map.has_key?(result.metadata, :cached_tokens)
    end

    test "Anthropic metadata is JSON-serializable" do
      {:ok, result} = Runtime.call(AnthropicTestAgent, %{message: "say hi"})

      state = %{
        output: result.output,
        usage: result.usage,
        model: result.model,
        metadata: Map.from_struct(result.metadata)
      }

      assert {:ok, _json} = Jason.encode(state)
    end
  end

  describe "OpenRouter metadata extraction" do
    @moduletag :openrouter

    defmodule OpenRouterTestAgent do
      @moduledoc false
      use Ash.Resource,
        domain: AshAgent.Integration.LiveProviderMetadataTest.TestDomain,
        extensions: [AshAgent.Resource]

      import AshAgent.Sigils

      resource do
        require_primary_key? false
      end

      agent do
        client("openrouter:x-ai/grok-4.1-fast:free", temperature: 0.0, max_tokens: 100)

        input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
        output_schema(Zoi.object(%{response: Zoi.string()}, coerce: true))

        instruction(~p"""
        Reply with JSON matching the output format exactly.
        {{ ctx.output_format }}
        Message: {{ message }}
        """)
      end
    end

    test "extracts usage from OpenRouter response" do
      {:ok, result} = Runtime.call(OpenRouterTestAgent, %{message: "say hi"})

      assert is_map(result.usage)
      assert result.usage[:input_tokens] > 0
      assert result.usage[:output_tokens] > 0
    end

    test "extracts model identifier from OpenRouter" do
      {:ok, result} = Runtime.call(OpenRouterTestAgent, %{message: "say hi"})

      assert is_binary(result.model)
    end

    test "OpenRouter result has Metadata struct" do
      {:ok, result} = Runtime.call(OpenRouterTestAgent, %{message: "say hi"})

      assert %Metadata{} = result.metadata
      assert result.metadata.provider == :req_llm
    end

    test "OpenRouter metadata is JSON-serializable" do
      {:ok, result} = Runtime.call(OpenRouterTestAgent, %{message: "say hi"})

      state = %{
        output: result.output,
        usage: result.usage,
        model: result.model,
        metadata: Map.from_struct(result.metadata)
      }

      assert {:ok, _json} = Jason.encode(state)
    end
  end
end
