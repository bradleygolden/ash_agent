defmodule AshAgent.Runtime.PromptRenderer do
  @moduledoc """
  Renders prompt templates using the Solid template engine.

  Supports both pre-parsed Solid templates and raw string templates,
  converting user arguments into template context variables.
  """

  @doc """
  Renders a prompt template with the given arguments and config.

  Returns `{:ok, rendered_string}` or `{:error, reason}`.

  ## Examples

      iex> render("Hello {{ name }}", %{name: "World"}, %{})
      {:ok, "Hello World"}

  """
  def render(template, args, config) when is_binary(template) do
    context = build_context(args, config)
    render_string_template(template, context)
  end

  def render(template, args, config) when is_struct(template, Solid.Template) do
    context = build_context(args, config)
    render_solid_template(template, context)
  end

  defp build_context(args, config) do
    base_context = Map.new(args, fn {k, v} -> {to_string(k), v} end)

    schema_instruction = build_output_format_instruction(config)
    Map.put(base_context, "output_format", schema_instruction)
  end

  defp build_output_format_instruction(_config) do
    "Return your response as valid JSON matching the specified schema."
  end

  @dialyzer {:nowarn_function, render_solid_template: 2}
  defp render_solid_template(template, context) do
    case Solid.render(template, context, []) do
      {:ok, rendered} ->
        {:ok, IO.iodata_to_binary(rendered)}

      {:error, errors, _partial} ->
        {:error, "Template render failed: #{inspect(errors)}"}
    end
  end

  @dialyzer {:nowarn_function, render_string_template: 2}
  defp render_string_template(template, context) do
    with {:ok, parsed} <- Solid.parse(template),
         {:ok, rendered} <- Solid.render(parsed, context, []) do
      {:ok, IO.iodata_to_binary(rendered)}
    else
      {:error, error} -> {:error, "Template parse failed: #{inspect(error)}"}
      {:error, errors, _partial} -> {:error, "Template render failed: #{inspect(errors)}"}
    end
  end
end
