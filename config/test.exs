import Config

# Disable domain validation in tests to allow test resources
# without requiring full domain registration
config :ash, :validate_domain_resource_inclusion?, false

# Set a fake API key for tests (will be intercepted by stub before hitting real API)
System.put_env("ANTHROPIC_API_KEY", "test-key-12345")

config :ash_agent, :req_llm_options, req_http_options: [plug: {Req.Test, AshAgent.LLMStub}]
