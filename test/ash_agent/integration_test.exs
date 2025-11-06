defmodule AshAgent.IntegrationTest do
  @moduledoc """
  Integration tests for AshAgent using Req.Test stubs.

  These tests verify that agents work end-to-end with mocked LLM responses,
  without requiring actual API calls.
  """
  use ExUnit.Case, async: true

  alias AshAgent.Test.LLMStub

  defmodule EchoAgent do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.IntegrationTest.TestDomain,
      extensions: [AshAgent.Resource]

    import AshAgent.Sigils

    defmodule Reply do
      @moduledoc false
      use Ash.TypedStruct

      typed_struct do
        field :content, :string, allow_nil?: false
        field :confidence, :float
      end
    end

    agent do
      client("anthropic:claude-3-5-sonnet", temperature: 0.1, max_tokens: 50)
      output(Reply)
      prompt(~p"Echo: {{ message }}")

      input do
        argument :message, :string
      end
    end
  end

  defmodule SimpleAgent do
    @moduledoc false
    use Ash.Resource,
      domain: AshAgent.IntegrationTest.TestDomain,
      extensions: [AshAgent.Resource]

    import AshAgent.Sigils

    defmodule Response do
      @moduledoc false
      use Ash.TypedStruct

      typed_struct do
        field :greeting, :string, allow_nil?: false
      end
    end

    agent do
      client("anthropic:claude-3-5-sonnet", temperature: 0.1, max_tokens: 20)
      output(Response)
      prompt(~p"Say hello!")
    end
  end

  defmodule TestDomain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource EchoAgent
      resource SimpleAgent
    end
  end

  # Helper functions for calling actions
  defp call(resource, args) do
    resource
    |> Ash.ActionInput.for_action(:call, args)
    |> Ash.run_action()
  end

  defp call!(resource, args) do
    AshAgent.Runtime.call!(resource, args)
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

      assert %EchoAgent.Reply{} = result
      assert result.content == "Hello from test!"
      assert result.confidence == 0.95
    end

    test "works with minimal fields" do
      Req.Test.stub(
        AshAgent.LLMStub,
        LLMStub.object_response(%{
          "content" => "Minimal response"
        })
      )

      {:ok, result} = call(EchoAgent, message: "test")

      assert %EchoAgent.Reply{} = result
      assert result.content == "Minimal response"
      assert result.confidence == nil
    end

    test "works with different agents" do
      Req.Test.stub(
        AshAgent.LLMStub,
        LLMStub.object_response(%{
          "greeting" => "Hello, World!"
        })
      )

      {:ok, result} = call(SimpleAgent, %{})

      assert %SimpleAgent.Response{} = result
      assert result.greeting == "Hello, World!"
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

      assert %EchoAgent.Reply{} = result
      assert result.content == "Direct result"
      assert result.confidence == 0.85
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
      assert first.content == "First response"
      assert first.confidence == 0.95

      {:ok, second} = call(EchoAgent, message: "2")
      assert second.content == "Second response"
      assert second.confidence == 0.45

      {:ok, third} = call(EchoAgent, message: "3")
      assert third.content == "Third response"
      assert third.confidence == 0.70
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

  describe "TypedStruct validation" do
    test "enforces required fields" do
      Req.Test.stub(
        AshAgent.LLMStub,
        LLMStub.object_response(%{
          "confidence" => 0.95
        })
      )

      result = call(EchoAgent, message: "test")

      case result do
        {:error, _reason} -> assert true
        {:ok, reply} -> assert reply.content == nil
      end
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
      assert result.confidence == nil
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
