defmodule AshAgent.Tools.Function do
  @moduledoc """
  Tool implementation for executing Elixir functions.

  Supports three function types:
  - MFA tuple: {Module, :function, args}
  - Anonymous function: fn args, context -> ... end
  - Module function reference: &Module.function/arity
  """

  @behaviour AshAgent.Tool

  defstruct [:name, :description, :function, :parameters]

  @type t :: %__MODULE__{
          name: atom(),
          description: String.t(),
          function: mfa() | function(),
          parameters: [parameter_spec()]
        }

  @type parameter_spec :: %{
          name: atom(),
          type: atom(),
          required: boolean(),
          description: String.t()
        }

  def new(opts) do
    %__MODULE__{
      name: Keyword.fetch!(opts, :name),
      description: Keyword.fetch!(opts, :description),
      function: Keyword.fetch!(opts, :function),
      parameters: Keyword.get(opts, :parameters, [])
    }
  end

  @impl true
  def name, do: :function

  @impl true
  def description, do: "Executes an Elixir function"

  @impl true
  def schema do
    %{
      name: "function",
      description: "Executes an Elixir function",
      parameters: %{
        type: :object,
        properties: %{},
        required: []
      }
    }
  end

  @impl true
  def execute(args, context) do
    tool = context.tool

    with {:ok, validated_args} <- validate_args(args, tool.parameters) do
      call_function(tool.function, validated_args, context)
    end
  end

  defp validate_args(args, parameter_specs) do
    required_params =
      parameter_specs
      |> Enum.filter(& &1[:required])
      |> Enum.map(& &1[:name])

    case find_missing_params(args, required_params) do
      [] ->
        validated = normalize_arg_keys(args)
        {:ok, validated}

      missing_params ->
        {:error, "Missing required parameters: #{inspect(missing_params)}"}
    end
  end

  defp find_missing_params(args, required_params) do
    Enum.filter(required_params, fn param ->
      not Map.has_key?(args, param) and not Map.has_key?(args, to_string(param))
    end)
  end

  defp normalize_arg_keys(args) do
    Enum.reduce(args, %{}, fn {key, value}, acc ->
      atom_key = if is_atom(key), do: key, else: String.to_existing_atom(key)
      Map.put(acc, atom_key, value)
    end)
  end

  defp call_function({module, function, extra_args}, args, context) when is_list(extra_args) do
    result = apply(module, function, [args | extra_args] ++ [context])
    normalize_result(result)
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp call_function({module, function, extra_args}, args, _context) do
    result = apply(module, function, [args | extra_args])
    normalize_result(result)
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp call_function(fun, args, context) when is_function(fun, 2) do
    result = fun.(args, context)
    normalize_result(result)
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp call_function(fun, args, _context) when is_function(fun, 1) do
    result = fun.(args)
    normalize_result(result)
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp call_function(invalid, _args, _context) do
    {:error, "Invalid function type: #{inspect(invalid)}"}
  end

  defp normalize_result({:ok, result}) when is_map(result), do: {:ok, result}
  defp normalize_result({:ok, result}), do: {:ok, %{result: result}}
  defp normalize_result({:error, _} = error), do: error
  defp normalize_result(result) when is_map(result), do: {:ok, result}
  defp normalize_result(result), do: {:ok, %{result: result}}
end
