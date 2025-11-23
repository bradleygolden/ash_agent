existing_clients = Application.get_env(:ash_baml, :clients, [])

Application.put_env(
  :ash_baml,
  :clients,
  Keyword.merge(
    existing_clients,
    [
      support: {AshAgent.Test.BamlClient, []},
      ollama: {AshAgent.Test.OllamaClient, baml_src: "test/support/ollama_baml/baml_src"}
    ]
  )
)

ExUnit.start(capture_log: true, exclude: [:integration])
