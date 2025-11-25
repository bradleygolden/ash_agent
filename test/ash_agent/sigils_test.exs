defmodule AshAgent.SigilsTest do
  use ExUnit.Case, async: true

  import AshAgent.Sigils

  defp render(template, context) do
    template
    |> Solid.render!(context)
    |> IO.iodata_to_binary()
  end

  describe "sigil_p/2" do
    test "parses simple template" do
      template = ~p"Hello, world!"

      assert %Solid.Template{} = template
    end

    test "parses template with variable" do
      template = ~p"Hello, {{ name }}!"

      assert %Solid.Template{} = template

      result = render(template, %{"name" => "Alice"})
      assert result == "Hello, Alice!"
    end

    test "parses template with multiple variables" do
      template = ~p"{{ greeting }}, {{ name }}! Welcome to {{ place }}."

      result =
        render(template, %{
          "greeting" => "Hello",
          "name" => "Bob",
          "place" => "AshAgent"
        })

      assert result == "Hello, Bob! Welcome to AshAgent."
    end

    test "parses multiline template" do
      template = ~p"""
      You are a helpful assistant.

      User: {{ message }}
      """

      result = render(template, %{"message" => "How are you?"})

      assert result =~ "You are a helpful assistant."
      assert result =~ "User: How are you?"
    end

    test "parses template with Liquid control flow" do
      template = ~p"""
      {% if show_greeting %}Hello!{% endif %}
      """

      result_shown = render(template, %{"show_greeting" => true})
      result_hidden = render(template, %{"show_greeting" => false})

      assert result_shown =~ "Hello!"
      refute result_hidden =~ "Hello!"
    end

    test "parses template with for loop" do
      template = ~p"""
      {% for item in items %}{{ item }}{% endfor %}
      """

      result = render(template, %{"items" => ["a", "b", "c"]})

      assert result =~ "abc"
    end

    test "parses template with filters" do
      template = ~p"{{ name | upcase }}"

      result = render(template, %{"name" => "alice"})

      assert result == "ALICE"
    end

    test "parses empty template" do
      template = ~p""

      result = render(template, %{})

      assert result == ""
    end

    test "parses template with whitespace only" do
      template = ~p"   "

      result = render(template, %{})

      assert result == "   "
    end

    test "parses template with special characters" do
      template = ~p"Price: ${{ price }} (including {{ tax }}% tax)"

      result = render(template, %{"price" => "100", "tax" => "10"})

      assert result == "Price: $100 (including 10% tax)"
    end

    test "rendering missing variable returns empty string" do
      template = ~p"Hello, {{ name }}!"

      result = render(template, %{})

      assert result == "Hello, !"
    end

    test "parses nested variable access" do
      template = ~p"{{ user.name }} is {{ user.age }} years old"

      result = render(template, %{"user" => %{"name" => "Charlie", "age" => "30"}})

      assert result == "Charlie is 30 years old"
    end

    test "parses template with comments" do
      template = ~p"""
      Hello{% comment %} this is hidden {% endcomment %}!
      """

      result = render(template, %{})

      assert result =~ "Hello"
      assert result =~ "!"
      refute result =~ "this is hidden"
    end
  end

  describe "sigil_p/2 compile-time validation" do
    test "invalid template raises CompileError" do
      assert_raise CompileError, fn ->
        Code.compile_string("""
        import AshAgent.Sigils
        ~p"{% if unclosed"
        """)
      end
    end

    test "unbalanced tags raise CompileError" do
      assert_raise CompileError, fn ->
        Code.compile_string("""
        import AshAgent.Sigils
        ~p"{% for item in items %}no endfor"
        """)
      end
    end
  end
end
