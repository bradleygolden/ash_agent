defmodule AshAgent.ToolConverterTest do
  use ExUnit.Case, async: true

  alias AshAgent.ToolConverter

  describe "to_json_schema/1" do
    test "converts tool definitions to JSON Schema format" do
      tool_definitions = [
        %{
          name: :greet,
          description: "Greet someone",
          parameters: [
            name: [type: :string, required: true, description: "Name to greet"]
          ]
        }
      ]

      schemas = ToolConverter.to_json_schema(tool_definitions)

      assert length(schemas) == 1
      schema = hd(schemas)

      assert schema["name"] == "greet"
      assert schema["description"] == "Greet someone"
      assert schema["parameters"]["type"] == "object"
      assert schema["parameters"]["properties"]["name"]["type"] == "string"
      assert schema["parameters"]["required"] == ["name"]
    end

    test "handles tools with no parameters" do
      tool_definitions = [
        %{
          name: :simple_tool,
          description: "A simple tool",
          parameters: []
        }
      ]

      schemas = ToolConverter.to_json_schema(tool_definitions)

      schema = hd(schemas)
      assert schema["name"] == "simple_tool"
      assert schema["parameters"]["properties"] == %{}
      assert schema["parameters"]["required"] == []
    end

    test "handles multiple tools" do
      tool_definitions = [
        %{
          name: :tool1,
          description: "First tool",
          parameters: [param1: [type: :string, required: true]]
        },
        %{
          name: :tool2,
          description: "Second tool",
          parameters: [param2: [type: :integer, required: false]]
        }
      ]

      schemas = ToolConverter.to_json_schema(tool_definitions)

      assert length(schemas) == 2
      assert Enum.at(schemas, 0)["name"] == "tool1"
      assert Enum.at(schemas, 1)["name"] == "tool2"
    end

    test "handles various parameter types" do
      tool_definitions = [
        %{
          name: :complex_tool,
          description: "Complex tool",
          parameters: [
            name: [type: :string, required: true, description: "Name"],
            age: [type: :integer, required: false, description: "Age"],
            score: [type: :float, required: false, description: "Score"],
            active: [type: :boolean, required: false, description: "Active"],
            id: [type: :uuid, required: true, description: "ID"]
          ]
        }
      ]

      schemas = ToolConverter.to_json_schema(tool_definitions)
      schema = hd(schemas)

      assert schema["parameters"]["properties"]["name"]["type"] == "string"
      assert schema["parameters"]["properties"]["age"]["type"] == "integer"
      assert schema["parameters"]["properties"]["score"]["type"] == "number"
      assert schema["parameters"]["properties"]["active"]["type"] == "boolean"
      assert schema["parameters"]["properties"]["id"]["type"] == "string"
      assert schema["parameters"]["required"] == ["name", "id"]
    end

    test "handles nil parameters" do
      tool_definitions = [
        %{
          name: :no_params,
          description: "No parameters",
          parameters: nil
        }
      ]

      schemas = ToolConverter.to_json_schema(tool_definitions)

      schema = hd(schemas)
      assert schema["parameters"]["properties"] == %{}
      assert schema["parameters"]["required"] == []
    end
  end
end

