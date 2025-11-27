defmodule AshAgent.Runtime.PromptRendererTest do
  use ExUnit.Case, async: true

  alias AshAgent.Error
  alias AshAgent.Runtime.PromptRenderer

  describe "render/3 with string template" do
    test "renders simple template with variables" do
      template = "Hello {{ name }}!"
      args = %{name: "World"}
      config = %{output_type: nil}

      assert {:ok, "Hello World!"} = PromptRenderer.render(template, args, config)
    end

    test "renders template with multiple variables" do
      template = "{{ greeting }} {{ name }}, you are {{ age }} years old."
      args = %{greeting: "Hello", name: "Alice", age: 30}
      config = %{output_type: nil}

      assert {:ok, rendered} = PromptRenderer.render(template, args, config)
      assert rendered == "Hello Alice, you are 30 years old."
    end

    test "renders template with atom keys in args" do
      template = "Value: {{ key }}"
      args = %{key: "test_value"}
      config = %{output_type: nil}

      assert {:ok, "Value: test_value"} = PromptRenderer.render(template, args, config)
    end

    test "renders template with string keys in args" do
      template = "Value: {{ key }}"
      args = %{"key" => "test_value"}
      config = %{output_type: nil}

      assert {:ok, "Value: test_value"} = PromptRenderer.render(template, args, config)
    end

    test "includes output_format in context" do
      template = "Format: {{ output_format }}"
      args = %{}
      config = %{output_type: nil}

      assert {:ok, rendered} = PromptRenderer.render(template, args, config)
      assert rendered =~ "JSON"
    end

    test "returns error for invalid template syntax" do
      template = "Hello {{ name"
      args = %{name: "World"}
      config = %{output_type: nil}

      assert {:error, %Error{type: :prompt_error}} =
               PromptRenderer.render(template, args, config)
    end

    test "handles empty template" do
      template = ""
      args = %{}
      config = %{output_type: nil}

      assert {:ok, ""} = PromptRenderer.render(template, args, config)
    end

    test "handles template without variables" do
      template = "Static text without variables"
      args = %{}
      config = %{output_type: nil}

      assert {:ok, "Static text without variables"} =
               PromptRenderer.render(template, args, config)
    end

    test "handles missing variable gracefully" do
      template = "Hello {{ name }}"
      args = %{}
      config = %{output_type: nil}

      # Solid renders missing variables as empty string
      assert {:ok, "Hello "} = PromptRenderer.render(template, args, config)
    end

    test "handles nested map values with string keys" do
      # Solid requires string keys for nested access
      template = "User: {{ user.name }}"
      args = %{user: %{"name" => "Alice"}}
      config = %{output_type: nil}

      assert {:ok, "User: Alice"} = PromptRenderer.render(template, args, config)
    end

    test "handles list values" do
      template = "{% for item in items %}{{ item }} {% endfor %}"
      args = %{items: ["a", "b", "c"]}
      config = %{output_type: nil}

      assert {:ok, rendered} = PromptRenderer.render(template, args, config)
      assert rendered =~ "a"
      assert rendered =~ "b"
      assert rendered =~ "c"
    end

    test "handles conditionals" do
      template = "{% if show %}Visible{% endif %}"
      args = %{show: true}
      config = %{output_type: nil}

      assert {:ok, "Visible"} = PromptRenderer.render(template, args, config)
    end

    test "handles false conditionals" do
      template = "{% if show %}Visible{% endif %}"
      args = %{show: false}
      config = %{output_type: nil}

      assert {:ok, ""} = PromptRenderer.render(template, args, config)
    end

    test "handles filters" do
      template = "{{ name | upcase }}"
      args = %{name: "hello"}
      config = %{output_type: nil}

      assert {:ok, "HELLO"} = PromptRenderer.render(template, args, config)
    end
  end

  describe "render/3 with pre-parsed Solid.Template" do
    test "renders pre-parsed template" do
      {:ok, parsed} = Solid.parse("Hello {{ name }}!")
      args = %{name: "World"}
      config = %{output_type: nil}

      assert {:ok, "Hello World!"} = PromptRenderer.render(parsed, args, config)
    end

    test "renders pre-parsed template with multiple variables" do
      {:ok, parsed} = Solid.parse("{{ a }} + {{ b }} = {{ c }}")
      args = %{a: 1, b: 2, c: 3}
      config = %{output_type: nil}

      assert {:ok, "1 + 2 = 3"} = PromptRenderer.render(parsed, args, config)
    end

    test "handles output_format in pre-parsed template" do
      {:ok, parsed} = Solid.parse("Format: {{ output_format }}")
      args = %{}
      config = %{output_type: nil}

      assert {:ok, rendered} = PromptRenderer.render(parsed, args, config)
      assert rendered =~ "JSON"
    end
  end

  describe "render/3 edge cases" do
    test "handles integer values" do
      template = "Count: {{ count }}"
      args = %{count: 42}
      config = %{output_type: nil}

      assert {:ok, "Count: 42"} = PromptRenderer.render(template, args, config)
    end

    test "handles float values" do
      template = "Score: {{ score }}"
      args = %{score: 3.14}
      config = %{output_type: nil}

      assert {:ok, rendered} = PromptRenderer.render(template, args, config)
      assert rendered =~ "3.14"
    end

    test "handles boolean values" do
      template = "Active: {{ active }}"
      args = %{active: true}
      config = %{output_type: nil}

      assert {:ok, "Active: true"} = PromptRenderer.render(template, args, config)
    end

    test "handles nil values" do
      template = "Value: {{ value }}"
      args = %{value: nil}
      config = %{output_type: nil}

      assert {:ok, "Value: "} = PromptRenderer.render(template, args, config)
    end

    test "handles multiline templates" do
      template = """
      Line 1: {{ a }}
      Line 2: {{ b }}
      Line 3: {{ c }}
      """

      args = %{a: "first", b: "second", c: "third"}
      config = %{output_type: nil}

      assert {:ok, rendered} = PromptRenderer.render(template, args, config)
      assert rendered =~ "Line 1: first"
      assert rendered =~ "Line 2: second"
      assert rendered =~ "Line 3: third"
    end

    test "handles special characters in values" do
      template = "Code: {{ code }}"
      args = %{code: "def foo() do\n  :ok\nend"}
      config = %{output_type: nil}

      assert {:ok, rendered} = PromptRenderer.render(template, args, config)
      assert rendered =~ "def foo()"
    end

    test "handles unicode in templates and values" do
      template = "Greeting: {{ greeting }}"
      args = %{greeting: "こんにちは"}
      config = %{output_type: nil}

      assert {:ok, "Greeting: こんにちは"} = PromptRenderer.render(template, args, config)
    end
  end
end
