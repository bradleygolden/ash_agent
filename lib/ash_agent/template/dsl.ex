defmodule AshAgent.Template.Dsl do
  @moduledoc false

  use Spark.Dsl.Extension,
    sections: [AshAgent.DSL.template_agent()],
    transformers: [],
    imports: [AshAgent.DSL, AshAgent.Sigils]
end
