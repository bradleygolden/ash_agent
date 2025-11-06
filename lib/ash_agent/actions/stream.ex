defmodule AshAgent.Actions.Stream do
  @moduledoc """
  Implementation for the `:stream` action on agent resources.

  This module is automatically used by agent resources to execute
  streaming LLM calls and return a stream of partial results.
  """

  use Ash.Resource.Actions.Implementation

  alias AshAgent.Runtime

  @doc """
  Executes the agent stream action.

  Called by Ash's action system to invoke the agent with streaming responses.
  Delegates to `AshAgent.Runtime.stream/2` which returns a stream of partial
  results as they arrive from the LLM.
  """
  @impl true
  def run(input, _opts, _context) do
    Runtime.stream(input.resource, input.arguments)
  end
end
