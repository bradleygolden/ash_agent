defmodule AshAgent.SchemaConverterTest do
  @moduledoc false
  use ExUnit.Case, async: true

  alias AshAgent.SchemaConverter
  alias AshAgent.Test.Reply

  defmodule NestedObject do
    use Ash.TypedStruct

    typed_struct do
      field :title, :string, allow_nil?: false
      field :count, :integer
    end
  end

  defmodule ComplexTypes do
    use Ash.TypedStruct

    typed_struct do
      field :nested_array, {:array, {:array, :string}}
      field :object_array, {:array, NestedObject}
      field :nested_object, NestedObject
      field :optional_field, :string
      field :required_field, :string, allow_nil?: false
    end
  end

  describe "to_req_llm_schema/1" do
    test "converts Ash.TypedStruct to req_llm schema" do
      schema = SchemaConverter.to_req_llm_schema(Reply)

      assert is_list(schema)
      assert Keyword.has_key?(schema, :content)
      assert Keyword.has_key?(schema, :confidence)

      content_opts = schema[:content]
      assert content_opts[:type] == :string
      assert content_opts[:required] == true

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

  describe "nested arrays" do
    test "converts nested arrays correctly" do
      schema = SchemaConverter.to_req_llm_schema(ComplexTypes)

      nested_array_opts = schema[:nested_array]
      assert nested_array_opts[:type] == {:array, {:array, :string}}
      assert nested_array_opts[:required] == false
    end

    test "converts arrays of objects" do
      schema = SchemaConverter.to_req_llm_schema(ComplexTypes)

      object_array_opts = schema[:object_array]
      assert {:array, {:object, _fields}} = object_array_opts[:type]
    end
  end

  describe "nested objects" do
    test "converts nested TypedStruct objects" do
      schema = SchemaConverter.to_req_llm_schema(ComplexTypes)

      nested_object_opts = schema[:nested_object]
      assert {:object, fields} = nested_object_opts[:type]
      assert Keyword.has_key?(fields, :title)
      assert Keyword.has_key?(fields, :count)

      title_opts = fields[:title]
      assert title_opts[:type] == :string
      assert title_opts[:required] == true

      count_opts = fields[:count]
      assert count_opts[:type] == :integer
      assert count_opts[:required] == false
    end
  end

  describe "optional vs required fields" do
    test "correctly identifies required fields (enforce: true)" do
      schema = SchemaConverter.to_req_llm_schema(ComplexTypes)

      required_opts = schema[:required_field]
      assert required_opts[:required] == true
    end

    test "correctly identifies optional fields" do
      schema = SchemaConverter.to_req_llm_schema(ComplexTypes)

      optional_opts = schema[:optional_field]
      assert optional_opts[:required] == false
    end
  end
end
