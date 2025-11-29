defmodule AshAgent.Runtime.LLMClientTest do
  use ExUnit.Case, async: true

  alias AshAgent.Error
  alias AshAgent.Runtime.LLMClient

  describe "parse_response/2 with Zoi schemas" do
    test "parses map with string keys using Zoi schema" do
      schema = Zoi.object(%{message: Zoi.string()}, coerce: true)
      response = %{"message" => "Hello"}

      assert {:ok, result} = LLMClient.parse_response(schema, response)
      assert result.message == "Hello"
    end

    test "parses map with atom keys using Zoi schema" do
      schema = Zoi.object(%{message: Zoi.string()}, coerce: true)
      response = %{message: "Hello"}

      assert {:ok, result} = LLMClient.parse_response(schema, response)
      assert result.message == "Hello"
    end

    test "parses complex response with Zoi schema" do
      schema =
        Zoi.object(
          %{
            title: Zoi.string(),
            description: Zoi.string() |> Zoi.optional(),
            score: Zoi.float() |> Zoi.optional(),
            tags: Zoi.list(Zoi.string()) |> Zoi.optional()
          },
          coerce: true
        )

      response = %{
        "title" => "Test Title",
        "description" => "Test description",
        "score" => 0.95,
        "tags" => ["elixir", "test"]
      }

      assert {:ok, result} = LLMClient.parse_response(schema, response)
      assert result.title == "Test Title"
      assert result.description == "Test description"
      assert result.score == 0.95
      assert result.tags == ["elixir", "test"]
    end

    test "returns error for invalid data" do
      schema = Zoi.object(%{message: Zoi.string()}, coerce: true)
      response = %{"message" => 123}

      assert {:error, %Error{type: :parse_error}} = LLMClient.parse_response(schema, response)
    end

    test "handles optional fields" do
      schema =
        Zoi.object(
          %{
            required_field: Zoi.string(),
            optional_field: Zoi.string() |> Zoi.optional()
          },
          coerce: true
        )

      response = %{"required_field" => "hello"}

      assert {:ok, result} = LLMClient.parse_response(schema, response)
      assert result.required_field == "hello"
      assert Map.get(result, :optional_field) == nil
    end
  end

  describe "parse_response/2 with primitive types" do
    test "parses string primitive" do
      response = %{text: "Hello world"}
      assert {:ok, "Hello world"} = LLMClient.parse_response(:string, response)
    end

    test "parses integer primitive" do
      response = %{text: "42"}
      assert {:ok, 42} = LLMClient.parse_response(:integer, response)
    end

    test "parses float primitive" do
      response = %{text: "3.14"}
      assert {:ok, 3.14} = LLMClient.parse_response(:float, response)
    end

    test "parses boolean primitive" do
      assert {:ok, true} = LLMClient.parse_response(:boolean, %{text: "true"})
      assert {:ok, false} = LLMClient.parse_response(:boolean, %{text: "false"})
    end
  end

  describe "parse_response/2 error handling" do
    test "returns error for nil response" do
      schema = Zoi.object(%{message: Zoi.string()}, coerce: true)
      assert {:error, %Error{type: :parse_error}} = LLMClient.parse_response(schema, nil)
    end

    test "returns error for string response with object schema" do
      schema = Zoi.object(%{message: Zoi.string()}, coerce: true)

      assert {:error, %Error{type: :parse_error}} =
               LLMClient.parse_response(schema, "plain string")
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
      schema = Zoi.object(%{message: Zoi.string()}, coerce: true)
      input_stream = Stream.map([%{message: "a"}, %{message: "b"}], & &1)

      result = LLMClient.stream_to_structs(input_stream, schema)
      assert %Stream{} = result
    end

    test "converts stream elements using Zoi schema" do
      schema = Zoi.object(%{message: Zoi.string()}, coerce: true)
      input_stream = Stream.map([%{"message" => "a"}, %{"message" => "b"}], & &1)

      result =
        input_stream
        |> LLMClient.stream_to_structs(schema)
        |> Enum.to_list()

      assert length(result) == 2
      assert Enum.all?(result, &match?(%{message: _}, &1))
    end

    test "handles function stream" do
      schema = Zoi.object(%{message: Zoi.string()}, coerce: true)

      stream_fn = fn acc, _fun ->
        {:suspended, acc, fn _ -> {:done, []} end}
      end

      result = LLMClient.stream_to_structs(stream_fn, schema)
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
