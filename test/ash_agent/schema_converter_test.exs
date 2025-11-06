defmodule AshAgent.SchemaConverterTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias AshAgent.SchemaConverter
  alias AshAgent.Test.Reply

  describe "to_req_llm_schema/1" do
    test "converts Ash.TypedStruct to req_llm schema" do
      # Use the Reply struct which is defined as a standalone module
      schema = SchemaConverter.to_req_llm_schema(Reply)

      assert is_list(schema)
      assert Keyword.has_key?(schema, :content)
      assert Keyword.has_key?(schema, :confidence)

      # Check content field (enforced)
      content_opts = schema[:content]
      assert content_opts[:type] == :string
      assert content_opts[:required] == true

      # Check confidence field (not enforced)
      confidence_opts = schema[:confidence]
      assert confidence_opts[:type] == :float
      assert confidence_opts[:required] == false
    end

    test "raises error for non-Ash.TypedStruct modules" do
      assert_raise ArgumentError,
                   ~r/does not appear to be an Ash\.TypedStruct.*Original error:/,
                   fn ->
                     SchemaConverter.to_req_llm_schema(String)
                   end
    end
  end
end
