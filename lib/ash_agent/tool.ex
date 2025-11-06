defmodule AshAgent.Tool do
  @moduledoc """
  Behavior for AshAgent tools that can be called by LLM agents.

  Tools represent functions that agents can invoke during execution.
  Each tool must provide a schema (for LLM understanding) and an
  execution function.
  """

  @type parameter_schema :: %{
          type: :string | :integer | :number | :boolean | :object | :array,
          required: boolean(),
          description: String.t(),
          properties: map(),
          items: map()
        }

  @type schema :: %{
          name: String.t(),
          description: String.t(),
          parameters: %{
            type: :object,
            properties: %{atom() => parameter_schema()},
            required: [atom()]
          }
        }

  @type execution_result :: {:ok, map()} | {:error, term()}

  @type context :: %{
          agent: module(),
          domain: module(),
          actor: term(),
          tenant: term()
        }

  @callback name() :: atom()
  @callback description() :: String.t()
  @callback schema() :: schema()
  @callback execute(args :: map(), context :: context()) :: execution_result()

  @doc """
  Validates that a module implements the Tool behavior correctly.
  """
  def validate_implementation!(module) do
    unless function_exported?(module, :name, 0) do
      raise ArgumentError, "Tool #{inspect(module)} must implement name/0"
    end

    unless function_exported?(module, :description, 0) do
      raise ArgumentError, "Tool #{inspect(module)} must implement description/0"
    end

    unless function_exported?(module, :schema, 0) do
      raise ArgumentError, "Tool #{inspect(module)} must implement schema/0"
    end

    unless function_exported?(module, :execute, 2) do
      raise ArgumentError, "Tool #{inspect(module)} must implement execute/2"
    end

    :ok
  end

  @doc """
  Builds a JSON Schema compatible tool schema from a tool module.
  """
  def to_json_schema(module) do
    module.schema()
  end
end
