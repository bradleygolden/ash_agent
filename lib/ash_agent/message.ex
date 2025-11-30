defmodule AshAgent.Message do
  @moduledoc """
  Represents a message in an agent conversation.

  Messages are the building blocks of agent context. Each message has a role
  that determines how it's interpreted by the LLM provider:

  - `:system` - System instruction that sets agent behavior
  - `:user` - User input or request
  - `:assistant` - Previous assistant responses (for multi-turn)

  ## Creating Messages

  Messages are typically created via generated functions on agent modules:

      # Create instruction message (validates against instruction_schema)
      ChatAgent.instruction(company_name: "Acme")
      #=> %AshAgent.Message{role: :system, content: "You are..."}

      # Create user message (validates against input_schema)
      ChatAgent.user(message: "Hello!")
      #=> %AshAgent.Message{role: :user, content: %{message: "Hello!"}}

  ## Usage in Context

  Messages are combined into a context for agent execution:

      context =
        [
          ChatAgent.instruction(company_name: "Acme"),
          ChatAgent.user(message: "Hello!")
        ]
        |> ChatAgent.context()

      ChatAgent.call(context)
  """

  defstruct [:role, :content, :metadata]

  @type role :: :system | :user | :assistant
  @type t :: %__MODULE__{
          role: role(),
          content: String.t() | map(),
          metadata: map() | nil
        }

  @doc """
  Creates a new system instruction message.
  """
  def system(content, metadata \\ nil) when is_binary(content) do
    %__MODULE__{role: :system, content: content, metadata: metadata}
  end

  @doc """
  Creates a new user message.
  """
  def user(content, metadata \\ nil) do
    %__MODULE__{role: :user, content: content, metadata: metadata}
  end

  @doc """
  Creates a new assistant message.
  """
  def assistant(content, metadata \\ nil) do
    %__MODULE__{role: :assistant, content: content, metadata: metadata}
  end

  @doc """
  Converts a message to the format expected by LLM providers.
  """
  def to_provider_format(%__MODULE__{role: role, content: content}) do
    %{
      role: to_string(role),
      content: format_content(content)
    }
  end

  defp format_content(content) when is_binary(content), do: content
  defp format_content(content) when is_map(content), do: Jason.encode!(content)
end
