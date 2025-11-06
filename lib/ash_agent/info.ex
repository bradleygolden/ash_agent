defmodule AshAgent.Info do
  @moduledoc """
  Introspection functions for AshAgent extensions.

  This module provides functions to retrieve configuration from resources and domains
  that use the AshAgent extensions.
  """

  use Spark.InfoGenerator, extension: AshAgent.Resource, sections: [:agent]
end
