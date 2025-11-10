defmodule AshAgent.Error do
  @moduledoc """
  Structured error types for AshAgent operations.

  All errors follow a consistent structure with a type, message, and optional details.
  """

  defexception [:type, :message, :details]

  @type t :: %__MODULE__{
          type: error_type(),
          message: String.t(),
          details: map()
        }

  @type error_type ::
          :config_error
          | :prompt_error
          | :schema_error
          | :llm_error
          | :parse_error
          | :hook_error
          | :validation_error
          | :budget_error

  def config_error(message, details \\ %{}) do
    %__MODULE__{
      type: :config_error,
      message: message,
      details: details
    }
  end

  def prompt_error(message, details \\ %{}) do
    %__MODULE__{
      type: :prompt_error,
      message: message,
      details: details
    }
  end

  def schema_error(message, details \\ %{}) do
    %__MODULE__{
      type: :schema_error,
      message: message,
      details: details
    }
  end

  def llm_error(message, details \\ %{}) do
    %__MODULE__{
      type: :llm_error,
      message: message,
      details: details
    }
  end

  def parse_error(message, details \\ %{}) do
    %__MODULE__{
      type: :parse_error,
      message: message,
      details: details
    }
  end

  def hook_error(message, details \\ %{}) do
    %__MODULE__{
      type: :hook_error,
      message: message,
      details: details
    }
  end

  def validation_error(message, details \\ %{}) do
    %__MODULE__{
      type: :validation_error,
      message: message,
      details: details
    }
  end

  def budget_error(message, details \\ %{}) do
    %__MODULE__{
      type: :budget_error,
      message: message,
      details: details
    }
  end

  def from_exception(exception, type \\ :llm_error, details \\ %{}) do
    %__MODULE__{
      type: type,
      message: Exception.message(exception),
      details: Map.merge(%{exception: exception.__struct__}, details)
    }
  end
end
