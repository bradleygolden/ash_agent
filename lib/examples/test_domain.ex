defmodule Examples.TestDomain do
  use Ash.Domain

  resources do
    resource Examples.DemoAgent
    resource Examples.MultiInputAgent
  end
end
