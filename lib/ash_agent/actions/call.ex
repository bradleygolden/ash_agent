defmodule AshAgent.Actions.Call do
  @moduledoc """
  Implementation for the `:call` action on agent resources.

  This module is automatically used by agent resources to execute
  synchronous LLM calls and return structured results.
  """

  use Ash.Resource.Actions.Implementation

  alias AshAgent.Runtime

  @impl true
  def run(input, _opts, _context) do
    Runtime.call(input.resource, input.arguments.context)
  end
end
