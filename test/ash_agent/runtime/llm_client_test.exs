defmodule AshAgent.Runtime.LLMClientTest do
  use ExUnit.Case, async: true

  alias AshAgent.Runtime.LLMClient
  alias AshAgent.Error
  alias AshAgent.Test.TestAgents

  defmodule TempStruct do
    defstruct [:message]
  end

  describe "parse_response/2 with map response" do
    test "parses map with string keys to struct" do
      response = %{"message" => "Hello"}

      assert {:ok, struct} = LLMClient.parse_response(TestAgents.SimpleOutput, response)
      assert %TestAgents.SimpleOutput{} = struct
      assert struct.message == "Hello"
    end

    test "parses map with atom keys to struct" do
      response = %{message: "Hello"}

      assert {:ok, struct} = LLMClient.parse_response(TestAgents.SimpleOutput, response)
      assert struct.message == "Hello"
    end

    test "parses complex response to struct" do
      response = %{
        "title" => "Test Title",
        "description" => "Test description",
        "score" => 0.95,
        "tags" => ["elixir", "test"]
      }

      assert {:ok, struct} = LLMClient.parse_response(TestAgents.ComplexOutput, response)
      assert %TestAgents.ComplexOutput{} = struct
      assert struct.title == "Test Title"
      assert struct.description == "Test description"
      assert struct.score == 0.95
      assert struct.tags == ["elixir", "test"]
    end

    test "returns error for non-existent atom keys" do
      unique_key = "nonexistent_key_#{System.unique_integer([:positive])}"
      response = %{unique_key => "value"}

      assert {:error, %Error{type: :parse_error}} =
               LLMClient.parse_response(TestAgents.SimpleOutput, response)
    end

    test "ignores extra atom keys and creates struct with provided values" do
      response = %{message: "hello", extra_atom_key: "ignored"}

      assert {:ok, struct} = LLMClient.parse_response(TestAgents.SimpleOutput, response)
      assert %TestAgents.SimpleOutput{message: "hello"} = struct
    end
  end

  describe "parse_response/2 with struct response" do
    test "returns struct directly if already the output type" do
      struct = %TestAgents.SimpleOutput{message: "Already a struct"}

      assert {:ok, ^struct} = LLMClient.parse_response(TestAgents.SimpleOutput, struct)
    end

    test "converts different struct to output type" do
      response = %TempStruct{message: "From different struct"}

      assert {:ok, struct} = LLMClient.parse_response(TestAgents.SimpleOutput, response)
      assert struct.message == "From different struct"
    end
  end

  describe "response_usage/2" do
    test "returns nil for unsupported response types" do
      assert nil == LLMClient.response_usage(:req_llm, %{})
    end

    test "returns nil for plain map without usage key" do
      assert nil == LLMClient.response_usage(:req_llm, %{data: "test"})
    end

    test "extracts usage from map with usage key for baml provider" do
      response = %{
        usage: %{input_tokens: 100, output_tokens: 50}
      }

      usage = LLMClient.response_usage(:baml, response)
      assert usage == %{input_tokens: 100, output_tokens: 50}
    end

    test "extracts usage from map with string usage key for baml provider" do
      response = %{
        "usage" => %{input_tokens: 100, output_tokens: 50}
      }

      usage = LLMClient.response_usage(:baml, response)
      assert usage == %{input_tokens: 100, output_tokens: 50}
    end
  end

  describe "response_usage/1" do
    test "returns nil for plain map" do
      assert nil == LLMClient.response_usage(%{data: "test"})
    end

    test "returns nil for string" do
      assert nil == LLMClient.response_usage("string response")
    end

    test "returns nil for list" do
      assert nil == LLMClient.response_usage([1, 2, 3])
    end
  end

  describe "stream_to_structs/2" do
    test "returns a stream" do
      # Create a simple stream
      input_stream = Stream.map([%{message: "a"}, %{message: "b"}], & &1)

      result = LLMClient.stream_to_structs(input_stream, TestAgents.SimpleOutput)
      assert %Stream{} = result
    end

    test "converts stream elements to structs" do
      input_stream = Stream.map([%{"message" => "a"}, %{"message" => "b"}], & &1)

      result =
        input_stream
        |> LLMClient.stream_to_structs(TestAgents.SimpleOutput)
        |> Enum.to_list()

      assert length(result) == 2
      assert Enum.all?(result, &match?(%TestAgents.SimpleOutput{}, &1))
    end

    test "handles function stream" do
      # Function-based stream
      stream_fn = fn acc, _fun ->
        {:suspended, acc, fn _ -> {:done, []} end}
      end

      result = LLMClient.stream_to_structs(stream_fn, TestAgents.SimpleOutput)
      assert is_struct(result, Stream) or is_function(result, 2)
    end
  end

  describe "generate_object/7" do
    test "returns error when provider resolution fails" do
      result =
        LLMClient.generate_object(
          NonExistentResource,
          "client",
          "prompt",
          [],
          [],
          %{},
          provider_override: :unknown_provider
        )

      assert {:error, %Error{}} = result
    end
  end

  describe "stream_object/7" do
    test "returns error when provider resolution fails" do
      result =
        LLMClient.stream_object(
          NonExistentResource,
          "client",
          "prompt",
          [],
          [],
          %{},
          provider_override: :unknown_provider
        )

      assert {:error, %Error{}} = result
    end
  end
end
