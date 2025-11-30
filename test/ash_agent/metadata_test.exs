defmodule AshAgent.MetadataTest do
  use ExUnit.Case, async: true

  alias AshAgent.Metadata

  describe "new/2" do
    test "creates empty metadata struct with defaults" do
      assert %Metadata{} = Metadata.new()
    end

    test "creates metadata from provider data" do
      provider_data = %{
        provider: :req_llm,
        total_cost: 0.01,
        reasoning_tokens: 64
      }

      result = Metadata.new(provider_data)

      assert %Metadata{
               provider: :req_llm,
               total_cost: 0.01,
               reasoning_tokens: 64
             } = result
    end

    test "creates metadata from runtime timing" do
      now = DateTime.utc_now()

      runtime_timing = %{
        started_at: now,
        completed_at: DateTime.add(now, 500, :millisecond),
        duration_ms: 500
      }

      result = Metadata.new(%{}, runtime_timing)

      assert %Metadata{
               started_at: ^now,
               duration_ms: 500
             } = result
    end

    test "merges provider data with runtime timing" do
      now = DateTime.utc_now()

      provider_data = %{
        provider: :baml,
        request_id: "req_123",
        num_attempts: 2
      }

      runtime_timing = %{
        started_at: now,
        duration_ms: 1234
      }

      result = Metadata.new(provider_data, runtime_timing)

      assert %Metadata{
               provider: :baml,
               request_id: "req_123",
               num_attempts: 2,
               started_at: ^now,
               duration_ms: 1234
             } = result
    end

    test "runtime timing overrides provider timing when both present" do
      provider_data = %{duration_ms: 100}
      runtime_timing = %{duration_ms: 200}

      result = Metadata.new(provider_data, runtime_timing)

      assert result.duration_ms == 200
    end

    test "handles keyword list input" do
      provider_data = [provider: :mock, total_cost: 0]

      result = Metadata.new(provider_data)

      assert %Metadata{provider: :mock, total_cost: 0} = result
    end

    test "handles non-map/non-list input gracefully" do
      result = Metadata.new(nil, "invalid")

      assert %Metadata{} = result
    end
  end

  describe "struct fields" do
    test "has all expected timing fields" do
      metadata = %Metadata{}

      assert Map.has_key?(metadata, :duration_ms)
      assert Map.has_key?(metadata, :time_to_first_token_ms)
      assert Map.has_key?(metadata, :started_at)
      assert Map.has_key?(metadata, :completed_at)
    end

    test "has all expected request tracing fields" do
      metadata = %Metadata{}

      assert Map.has_key?(metadata, :request_id)
      assert Map.has_key?(metadata, :provider)
      assert Map.has_key?(metadata, :client_name)
    end

    test "has all expected execution detail fields" do
      metadata = %Metadata{}

      assert Map.has_key?(metadata, :num_attempts)
      assert Map.has_key?(metadata, :tags)
    end

    test "has all expected extended usage fields" do
      metadata = %Metadata{}

      assert Map.has_key?(metadata, :reasoning_tokens)
      assert Map.has_key?(metadata, :cached_tokens)
      assert Map.has_key?(metadata, :input_cost)
      assert Map.has_key?(metadata, :output_cost)
      assert Map.has_key?(metadata, :total_cost)
    end

    test "has raw_http_response for debugging" do
      metadata = %Metadata{}

      assert Map.has_key?(metadata, :raw_http_response)
    end
  end

  describe "req_llm metadata pattern" do
    test "matches expected req_llm metadata shape" do
      req_llm_metadata = %{
        provider: :req_llm,
        reasoning_tokens: 128,
        cached_tokens: 50,
        input_cost: 0.001,
        output_cost: 0.002,
        total_cost: 0.003
      }

      result = Metadata.new(req_llm_metadata)

      assert result.provider == :req_llm
      assert result.reasoning_tokens == 128
      assert result.cached_tokens == 50
      assert result.input_cost == 0.001
      assert result.output_cost == 0.002
      assert result.total_cost == 0.003
    end
  end

  describe "baml metadata pattern" do
    test "matches expected baml metadata shape" do
      now = DateTime.utc_now()

      baml_metadata = %{
        provider: :baml,
        duration_ms: 1500,
        time_to_first_token_ms: 200,
        started_at: now,
        request_id: "baml_req_abc",
        client_name: "SupportAgent",
        num_attempts: 1,
        tags: %{"environment" => "production"},
        raw_http_response: "{\"content\": \"hello\"}"
      }

      result = Metadata.new(baml_metadata)

      assert result.provider == :baml
      assert result.duration_ms == 1500
      assert result.time_to_first_token_ms == 200
      assert result.started_at == now
      assert result.request_id == "baml_req_abc"
      assert result.client_name == "SupportAgent"
      assert result.num_attempts == 1
      assert result.tags == %{"environment" => "production"}
      assert result.raw_http_response == "{\"content\": \"hello\"}"
    end
  end

  describe "mock metadata pattern" do
    test "accepts configurable metadata from mock provider" do
      mock_metadata = %{
        provider: :mock,
        duration_ms: 10,
        request_id: "mock_123"
      }

      result = Metadata.new(mock_metadata)

      assert result.provider == :mock
      assert result.duration_ms == 10
      assert result.request_id == "mock_123"
    end
  end
end
