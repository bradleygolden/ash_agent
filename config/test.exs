import Config

# Disable domain validation in tests to allow test resources
# without requiring full domain registration
config :ash, :validate_domain_resource_inclusion?, false

# Set a fake API key for tests (will be intercepted by stub before hitting real API)
System.put_env("ANTHROPIC_API_KEY", "test-key-12345")

config :ash_agent, :req_llm_options, req_http_options: [plug: {Req.Test, AshAgent.LLMStub}]

config :ash_agent,
  baml_clients: [
    support: {AshAgent.Test.BamlClient, []},
    ollama: {AshAgent.Test.OllamaClient, baml_src: "test/support/ollama_baml/baml_src"},
    ollama_live: {AshAgent.Test.OllamaLiveClient, baml_src: "test/support/ollama_baml/baml_src"}
  ]

config :ash_baml,
  clients: [
    test: {AshBaml.Test.BamlClient, baml_src: "../ash_baml/test/support/fixtures/baml_src"},
    thinking: {AshAgent.Test.ThinkingBamlClient, []},
    ollama_live: {AshAgent.Test.OllamaLiveClient, []}
  ]

config :req_llm, :openai, base_url: "http://localhost:11434/v1"

if Code.ensure_loaded?(ReqLLM) do
  ReqLLM.put_key(:openai_api_key, "ollama")
end

# Keep test runs to plain ExUnit output (no logger noise)
config :logger, level: :error
