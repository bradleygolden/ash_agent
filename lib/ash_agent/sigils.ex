defmodule AshAgent.Sigils do
  @moduledoc """
  Custom sigils for AshAgent prompts.

  Provides the `~p` sigil for defining Liquid-syntax prompts with compile-time validation.
  """

  @doc """
  Sigil for prompt templates using Liquid syntax.

  The `~p` sigil wraps Solid's template parser, providing a convenient way to define
  prompts that will be validated at compile time.

  ## Examples

      prompt ~p\"\"\"
      You are a helpful assistant.

      {{ output_format }}

      User: {{ message }}
      \"\"\"

  ## Modifiers

  No modifiers are currently supported.
  """
  defmacro sigil_p(term, _modifiers) do
    quote do
      case Solid.parse(unquote(term)) do
        {:ok, template} ->
          template

        {:error, error} ->
          raise CompileError,
            description: "Invalid Liquid template: #{inspect(error)}",
            file: __ENV__.file,
            line: __ENV__.line
      end
    end
  end
end
