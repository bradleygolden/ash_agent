defmodule Examples.TestDomain do
  use Ash.Domain,
    validate_config_inclusion?: false

  resources do
    resource Examples.DemoAgent
    resource Examples.MultiInputAgent
  end
end
