defmodule AshAgent.SchemaConverterTest do
  @moduledoc false
  use ExUnit.Case, async: true
  use ExUnitProperties

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

  describe "property-based tests" do
    property "always returns a keyword list" do
      check all(_iteration <- integer(1..10)) do
        schema = SchemaConverter.to_req_llm_schema(Reply)
        assert is_list(schema)
        assert Keyword.keyword?(schema)
      end
    end

    property "all fields have type and required keys" do
      check all(_iteration <- integer(1..10)) do
        schema = SchemaConverter.to_req_llm_schema(Reply)

        for {_field_name, field_opts} <- schema do
          assert Keyword.has_key?(field_opts, :type)
          assert Keyword.has_key?(field_opts, :required)
          assert is_boolean(field_opts[:required])
        end
      end
    end

    property "required flag matches field constraints" do
      check all(_iteration <- integer(1..10)) do
        schema = SchemaConverter.to_req_llm_schema(ComplexTypes)

        required_field = schema[:required_field]
        assert required_field[:required] == true

        optional_field = schema[:optional_field]
        assert optional_field[:required] == false
      end
    end

    property "nested arrays maintain structure" do
      check all(_iteration <- integer(1..10)) do
        schema = SchemaConverter.to_req_llm_schema(ComplexTypes)

        nested_array = schema[:nested_array]
        assert {:array, {:array, :string}} = nested_array[:type]
      end
    end

    property "nested objects maintain field structure" do
      check all(_iteration <- integer(1..10)) do
        schema = SchemaConverter.to_req_llm_schema(ComplexTypes)

        nested_object = schema[:nested_object]
        assert {:object, fields} = nested_object[:type]
        assert Keyword.keyword?(fields)
        assert Keyword.has_key?(fields, :title)
        assert Keyword.has_key?(fields, :count)
      end
    end

    property "type mappings are consistent" do
      check all(_iteration <- integer(1..20)) do
        schema = SchemaConverter.to_req_llm_schema(Reply)

        content_type = schema[:content][:type]
        assert content_type == :string

        confidence_type = schema[:confidence][:type]
        assert confidence_type == :float
      end
    end
  end
end
