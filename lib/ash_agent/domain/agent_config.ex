defmodule AshAgent.Domain.AgentConfig do
  @moduledoc """
  Configuration struct for agent templates registered in a domain.

  Used by the `agent` entity in the `agents` DSL section.
  """

  defstruct [:template, :client, :provider, :as, :extensions, :__spark_metadata__]
end
