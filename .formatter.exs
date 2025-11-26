[
  inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"],
  plugins: [Spark.Formatter],
  import_deps: [:ash, :spark],
  locals_without_parens: [
    client: 1,
    client: 2,
    provider: 1,
    provider: 2,
    output: 1,
    prompt: 1,
    hooks: 1,
    input: 0,
    argument: 2,
    argument: 3,
    agents: 0,
    agents: 1,
    agent: 1,
    agent: 2,
    as: 1,
    extensions: 1
  ],
  export: [
    locals_without_parens: [
      client: 1,
      client: 2,
      provider: 1,
      provider: 2,
      output: 1,
      prompt: 1,
      hooks: 1,
      input: 0,
      argument: 2,
      argument: 3,
      agents: 0,
      agents: 1,
      agent: 1,
      agent: 2,
      as: 1,
      extensions: 1
    ]
  ]
]
