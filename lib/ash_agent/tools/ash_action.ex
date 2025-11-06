defmodule AshAgent.Tools.AshAction do
  @moduledoc """
  Tool implementation for executing Ash actions.

  Wraps Ash resource actions and makes them available as agent tools.
  """

  @behaviour AshAgent.Tool

  alias Ash.Resource.Info

  defstruct [:name, :description, :resource, :action_name, :parameters]

  @type t :: %__MODULE__{
          name: atom(),
          description: String.t(),
          resource: module(),
          action_name: atom(),
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
      resource: Keyword.fetch!(opts, :resource),
      action_name: Keyword.fetch!(opts, :action_name),
      parameters: Keyword.get(opts, :parameters, [])
    }
  end

  @impl true
  def name, do: :ash_action

  @impl true
  def description, do: "Executes an Ash action"

  @impl true
  def schema do
    %{
      name: "ash_action",
      description: "Executes an Ash action",
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
      call_ash_action(tool, validated_args, context)
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

  defp call_ash_action(tool, args, context) do
    opts = [
      actor: context[:actor],
      tenant: context[:tenant]
    ]

    action = Info.action(tool.resource, tool.action_name)

    result =
      case action.type do
        :read ->
          tool.resource
          |> Ash.Query.for_read(tool.action_name, args, opts)
          |> Ash.read()

        :create ->
          tool.resource
          |> Ash.Changeset.for_create(tool.action_name, args, opts)
          |> Ash.create()

        :update ->
          record = context[:record] || get_record_for_update(tool, args, opts)

          record
          |> Ash.Changeset.for_update(tool.action_name, args, opts)
          |> Ash.update()

        :destroy ->
          record = context[:record] || get_record_for_destroy(tool, args, opts)

          record
          |> Ash.Changeset.for_destroy(tool.action_name, args, opts)
          |> Ash.destroy()
      end

    case result do
      {:ok, record} -> {:ok, normalize_ash_result(record)}
      {:error, error} -> {:error, format_ash_error(error)}
    end
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp get_record_for_update(tool, args, opts) do
    id = args[:id] || args["id"]

    case Ash.get(tool.resource, id, opts) do
      {:ok, record} -> record
      {:error, _} -> raise "Record not found for update"
    end
  end

  defp get_record_for_destroy(tool, args, opts) do
    id = args[:id] || args["id"]

    case Ash.get(tool.resource, id, opts) do
      {:ok, record} -> record
      {:error, _} -> raise "Record not found for destroy"
    end
  end

  defp normalize_ash_result(%Ash.BulkResult{} = bulk_result) do
    %{
      records: bulk_result.records,
      count: length(bulk_result.records),
      errors: bulk_result.errors
    }
  end

  defp normalize_ash_result(%Ash.Page.Offset{} = page) do
    %{
      results: page.results,
      count: page.count,
      more?: page.more?
    }
  end

  defp normalize_ash_result(%Ash.Page.Keyset{} = page) do
    %{
      results: page.results,
      more?: page.more?,
      before: page.before,
      after: page.after
    }
  end

  defp normalize_ash_result(result) when is_struct(result) do
    result
    |> Map.from_struct()
    |> Map.drop([:__meta__, :__metadata__, :aggregates, :calculations])
  end

  defp normalize_ash_result(result), do: result

  defp format_ash_error(%Ash.Error.Invalid{errors: errors}) do
    Enum.map_join(errors, ", ", &format_single_error/1)
  end

  defp format_ash_error(error) do
    Exception.message(error)
  end

  defp format_single_error(%{message: message}), do: message
  defp format_single_error(error), do: inspect(error)
end
