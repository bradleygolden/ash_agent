# Used by "mix format"
[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  plugins: [Spark.Formatter],
  import_deps: [:ash, :spark],
  locals_without_parens: [
    # AshAgent DSL - agent section
    client: 1,
    client: 2,
    output: 1,
    prompt: 1,

    # AshAgent DSL - input section
    input: 0,
    argument: 2,
    argument: 3
  ],
  export: [
    locals_without_parens: [
      # AshAgent DSL - agent section
      client: 1,
      client: 2,
      output: 1,
      prompt: 1,

      # AshAgent DSL - input section
      input: 0,
      argument: 2,
      argument: 3
    ]
  ]
]
