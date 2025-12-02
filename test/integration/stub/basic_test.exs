defmodule AshAgent.Integration.Stub.BasicTest do
  @moduledoc """
  Integration tests for AshAgent using Req.Test stubs.

  These tests verify that agents work end-to-end with mocked LLM responses,
  without requiring actual API calls.
  """
  use AshAgent.IntegrationCase

  alias AshAgent.Test.LLMStub

  defmodule TestDomain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      allow_unregistered? true
    end
  end

  defmodule EchoAgent do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.Integration.Stub.BasicTest.TestDomain,
      extensions: [AshAgent.Resource]

    import AshAgent.Sigils

    resource do
      require_primary_key? false
    end

    agent do
      client("anthropic:claude-3-5-sonnet", temperature: 0.1, max_tokens: 50)
      input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))

      output_schema(
        Zoi.object(
          %{content: Zoi.string(), confidence: Zoi.float() |> Zoi.optional()},
          coerce: true
        )
      )

      instruction(~p"Echo: {{ message }}")
    end
  end

  defmodule SimpleAgent do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.Integration.Stub.BasicTest.TestDomain,
      extensions: [AshAgent.Resource]

    import AshAgent.Sigils

    resource do
      require_primary_key? false
    end

    agent do
      client("anthropic:claude-3-5-sonnet", temperature: 0.1, max_tokens: 20)
      input_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
      output_schema(Zoi.object(%{greeting: Zoi.string()}, coerce: true))
      instruction(~p"Say hello!")
    end
  end

  defp call(resource, args) do
    args = if is_list(args), do: Map.new(args), else: args

    case AshAgent.Runtime.call(resource, args) do
      {:ok, %AshAgent.Result{output: output}} -> {:ok, output}
      {:error, _} = error -> error
    end
  end

  defp call!(resource, args) do
    args = if is_list(args), do: Map.new(args), else: args
    %AshAgent.Result{output: output} = AshAgent.Runtime.call!(resource, args)
    output
  end

  describe "call/1" do
    test "returns structured response" do
      Req.Test.stub(
        AshAgent.LLMStub,
        LLMStub.object_response(%{
          "content" => "Hello from test!",
          "confidence" => 0.95
        })
      )

      {:ok, result} = call(EchoAgent, message: "test")

      assert %{content: "Hello from test!", confidence: 0.95} = result
    end

    test "works with minimal fields" do
      Req.Test.stub(
        AshAgent.LLMStub,
        LLMStub.object_response(%{
          "content" => "Minimal response"
        })
      )

      {:ok, result} = call(EchoAgent, message: "test")

      assert %{content: "Minimal response"} = result
      assert Map.get(result, :confidence) == nil
    end

    test "works with different agents" do
      Req.Test.stub(
        AshAgent.LLMStub,
        LLMStub.object_response(%{
          "greeting" => "Hello, World!"
        })
      )

      {:ok, result} = call(SimpleAgent, %{})

      assert %{greeting: "Hello, World!"} = result
    end

    test "handles API errors gracefully" do
      Req.Test.stub(AshAgent.LLMStub, LLMStub.error_response(500, "Server error"))

      result = call(EchoAgent, message: "test")

      assert {:error, _reason} = result
    end

    test "handles rate limiting errors" do
      Req.Test.stub(AshAgent.LLMStub, LLMStub.error_response(429, "Rate limit exceeded"))

      result = call(EchoAgent, message: "test")

      assert {:error, _reason} = result
    end

    test "handles network timeouts" do
      Req.Test.stub(AshAgent.LLMStub, LLMStub.timeout_error())

      result = call(EchoAgent, message: "test")

      assert {:error, _reason} = result
    end

    test "handles connection refused" do
      Req.Test.stub(AshAgent.LLMStub, LLMStub.connection_refused())

      result = call(EchoAgent, message: "test")

      assert {:error, _reason} = result
    end
  end

  describe "call!/1" do
    test "returns result directly on success" do
      Req.Test.stub(
        AshAgent.LLMStub,
        LLMStub.object_response(%{
          "content" => "Direct result",
          "confidence" => 0.85
        })
      )

      result = call!(EchoAgent, message: "test")

      assert %{content: "Direct result", confidence: 0.85} = result
    end

    test "raises on API error" do
      Req.Test.stub(AshAgent.LLMStub, LLMStub.error_response(500))

      assert_raise AshAgent.Error, fn ->
        call!(EchoAgent, message: "test")
      end
    end

    test "raises on network error" do
      Req.Test.stub(AshAgent.LLMStub, LLMStub.timeout_error())

      assert_raise AshAgent.Error, fn ->
        call!(EchoAgent, message: "test")
      end
    end
  end

  describe "with Req.Test.expect" do
    test "verifies exact number of calls" do
      Req.Test.expect(
        AshAgent.LLMStub,
        2,
        LLMStub.object_response(%{
          "content" => "Expected call",
          "confidence" => 0.9
        })
      )

      {:ok, result1} = call(EchoAgent, message: "first")
      assert result1.content == "Expected call"

      {:ok, result2} = call(EchoAgent, message: "second")
      assert result2.content == "Expected call"

      {:error, error} = call(EchoAgent, message: "third")
      assert is_struct(error)
      error_message = Exception.message(error)
      assert error_message =~ "LLM generation failed"
    end

    test "handles sequential different responses" do
      Req.Test.expect(
        AshAgent.LLMStub,
        LLMStub.object_response(%{
          "content" => "First response",
          "confidence" => 0.95
        })
      )

      Req.Test.expect(
        AshAgent.LLMStub,
        LLMStub.object_response(%{
          "content" => "Second response",
          "confidence" => 0.45
        })
      )

      Req.Test.expect(
        AshAgent.LLMStub,
        LLMStub.object_response(%{
          "content" => "Third response",
          "confidence" => 0.70
        })
      )

      {:ok, first} = call(EchoAgent, message: "1")
      assert %{content: "First response", confidence: 0.95} = first

      {:ok, second} = call(EchoAgent, message: "2")
      assert %{content: "Second response", confidence: 0.45} = second

      {:ok, third} = call(EchoAgent, message: "3")
      assert %{content: "Third response", confidence: 0.70} = third
    end

    test "simulates retry scenario with error then success" do
      Req.Test.expect(AshAgent.LLMStub, LLMStub.error_response(500))

      Req.Test.expect(
        AshAgent.LLMStub,
        LLMStub.object_response(%{
          "content" => "Success after retry",
          "confidence" => 0.88
        })
      )

      {:ok, result} = call(EchoAgent, message: "test")
      assert result.content == "Success after retry"
    end
  end

  describe "prompt variable interpolation" do
    test "variables are accessible in prompt" do
      Req.Test.stub(
        AshAgent.LLMStub,
        LLMStub.object_response(%{
          "content" => "Response with variables",
          "confidence" => 0.9
        })
      )

      {:ok, result} = call(EchoAgent, message: "test message")

      assert result.content == "Response with variables"
    end

    test "handles empty variables" do
      Req.Test.stub(
        AshAgent.LLMStub,
        LLMStub.object_response(%{
          "content" => "Empty var response"
        })
      )

      {:ok, result} = call(EchoAgent, message: "")

      assert result.content == "Empty var response"
    end
  end

  describe "Zoi schema validation" do
    test "enforces required fields" do
      Req.Test.stub(
        AshAgent.LLMStub,
        LLMStub.object_response(%{
          "confidence" => 0.95
        })
      )

      result = call(EchoAgent, message: "test")

      assert {:error, _reason} = result
    end

    test "accepts nil for optional fields" do
      Req.Test.stub(
        AshAgent.LLMStub,
        LLMStub.object_response(%{
          "content" => "Required content here"
        })
      )

      {:ok, result} = call(EchoAgent, message: "test")

      assert result.content == "Required content here"
      assert Map.get(result, :confidence) == nil
    end

    test "type-checks field values" do
      Req.Test.stub(
        AshAgent.LLMStub,
        LLMStub.object_response(%{
          "content" => "Valid content",
          "confidence" => 0.75
        })
      )

      {:ok, result} = call(EchoAgent, message: "test")

      assert result.content == "Valid content"
      assert result.confidence == 0.75
      assert is_float(result.confidence)
    end
  end
end
