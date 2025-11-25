defmodule AshAgent.ErrorTest do
  use ExUnit.Case, async: true

  alias AshAgent.Error

  describe "config_error/2" do
    test "creates error with :config_error type" do
      error = Error.config_error("Invalid configuration")

      assert %Error{} = error
      assert error.type == :config_error
      assert error.message == "Invalid configuration"
      assert error.details == %{}
    end

    test "creates error with details" do
      error = Error.config_error("Missing key", %{key: :api_key, provider: :anthropic})

      assert error.type == :config_error
      assert error.message == "Missing key"
      assert error.details == %{key: :api_key, provider: :anthropic}
    end
  end

  describe "prompt_error/2" do
    test "creates error with :prompt_error type" do
      error = Error.prompt_error("Invalid template")

      assert %Error{} = error
      assert error.type == :prompt_error
      assert error.message == "Invalid template"
      assert error.details == %{}
    end

    test "creates error with details" do
      error = Error.prompt_error("Syntax error", %{line: 5, column: 10})

      assert error.type == :prompt_error
      assert error.details == %{line: 5, column: 10}
    end
  end

  describe "schema_error/2" do
    test "creates error with :schema_error type" do
      error = Error.schema_error("Invalid schema definition")

      assert %Error{} = error
      assert error.type == :schema_error
      assert error.message == "Invalid schema definition"
      assert error.details == %{}
    end

    test "creates error with details" do
      error = Error.schema_error("Unknown type", %{field: :age, type: :unknown})

      assert error.type == :schema_error
      assert error.details == %{field: :age, type: :unknown}
    end
  end

  describe "llm_error/2" do
    test "creates error with :llm_error type" do
      error = Error.llm_error("API call failed")

      assert %Error{} = error
      assert error.type == :llm_error
      assert error.message == "API call failed"
      assert error.details == %{}
    end

    test "creates error with details" do
      error = Error.llm_error("Rate limited", %{retry_after: 60, status: 429})

      assert error.type == :llm_error
      assert error.details == %{retry_after: 60, status: 429}
    end
  end

  describe "parse_error/2" do
    test "creates error with :parse_error type" do
      error = Error.parse_error("Failed to parse response")

      assert %Error{} = error
      assert error.type == :parse_error
      assert error.message == "Failed to parse response"
      assert error.details == %{}
    end

    test "creates error with details" do
      error = Error.parse_error("Invalid JSON", %{raw: "{invalid}"})

      assert error.type == :parse_error
      assert error.details == %{raw: "{invalid}"}
    end
  end

  describe "hook_error/2" do
    test "creates error with :hook_error type" do
      error = Error.hook_error("Hook execution failed")

      assert %Error{} = error
      assert error.type == :hook_error
      assert error.message == "Hook execution failed"
      assert error.details == %{}
    end

    test "creates error with details" do
      error = Error.hook_error("Timeout", %{hook: :pre_call, timeout: 5000})

      assert error.type == :hook_error
      assert error.details == %{hook: :pre_call, timeout: 5000}
    end
  end

  describe "validation_error/2" do
    test "creates error with :validation_error type" do
      error = Error.validation_error("Input validation failed")

      assert %Error{} = error
      assert error.type == :validation_error
      assert error.message == "Input validation failed"
      assert error.details == %{}
    end

    test "creates error with details" do
      error = Error.validation_error("Required field missing", %{field: :name})

      assert error.type == :validation_error
      assert error.details == %{field: :name}
    end
  end

  describe "budget_error/2" do
    test "creates error with :budget_error type" do
      error = Error.budget_error("Token budget exceeded")

      assert %Error{} = error
      assert error.type == :budget_error
      assert error.message == "Token budget exceeded"
      assert error.details == %{}
    end

    test "creates error with details" do
      error = Error.budget_error("Budget limit reached", %{used: 50_000, limit: 40_000})

      assert error.type == :budget_error
      assert error.details == %{used: 50_000, limit: 40_000}
    end
  end

  describe "from_exception/3" do
    test "creates error from exception with default type" do
      exception = RuntimeError.exception("Something went wrong")

      error = Error.from_exception(exception)

      assert %Error{} = error
      assert error.type == :llm_error
      assert error.message == "Something went wrong"
      assert error.details == %{exception: RuntimeError}
    end

    test "creates error from exception with custom type" do
      exception = ArgumentError.exception("Invalid argument")

      error = Error.from_exception(exception, :validation_error)

      assert error.type == :validation_error
      assert error.message == "Invalid argument"
      assert error.details == %{exception: ArgumentError}
    end

    test "creates error from exception with additional details" do
      exception = RuntimeError.exception("Network error")

      error = Error.from_exception(exception, :llm_error, %{endpoint: "/api/chat"})

      assert error.type == :llm_error
      assert error.message == "Network error"
      assert error.details == %{exception: RuntimeError, endpoint: "/api/chat"}
    end

    test "merges details preserving exception module" do
      exception = KeyError.exception(key: :missing, term: %{})

      error = Error.from_exception(exception, :config_error, %{context: "loading"})

      assert error.details.exception == KeyError
      assert error.details.context == "loading"
    end
  end

  describe "Exception behaviour" do
    test "error is an exception" do
      error = Error.config_error("Test")

      assert Exception.exception?(error)
    end

    test "message/1 returns the error message" do
      error = Error.llm_error("API timeout")

      assert Exception.message(error) == "API timeout"
    end

    test "can raise and rescue error" do
      error = Error.validation_error("Bad input")

      assert_raise Error, "Bad input", fn ->
        raise error
      end
    end

    test "can pattern match on type when rescuing" do
      error = Error.budget_error("Over limit")

      result =
        try do
          raise error
        rescue
          e in Error ->
            e.type
        end

      assert result == :budget_error
    end
  end

  describe "error type coverage" do
    test "all error types are valid" do
      types = [
        :config_error,
        :prompt_error,
        :schema_error,
        :llm_error,
        :parse_error,
        :hook_error,
        :validation_error,
        :budget_error
      ]

      for type <- types do
        error_fn = String.to_existing_atom("#{type}")

        error = apply(Error, error_fn, ["test message"])

        assert error.type == type
      end
    end
  end
end
