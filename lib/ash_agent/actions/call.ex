defmodule AshAgent.Actions.Call do
  @moduledoc """
  Implementation for the `:call` action on agent resources.

  This module is automatically used by agent resources to execute
  synchronous LLM calls and return structured results.
  """

  use Ash.Resource.Actions.Implementation

  alias AshAgent.Runtime

  @doc """
  Executes the agent call action.

  Called by Ash's action system to invoke the agent synchronously and return
  a structured response. Delegates to `AshAgent.Runtime.call/2` with the
  resource module and input arguments.
  """
  @impl true
  def run(input, _opts, _context) do
    Runtime.call(input.resource, input.arguments)
  end
end
