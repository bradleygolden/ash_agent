# AshAgent Dev Notes

- Use imperative mood for all git commits
- Never use @spec annotations unless absolutely necessary due to some bug in a client library or similar.
- Do not add new code comments when editing files. Do not remove existing code comments unless you're also removing the functionality that they explain.

## Tooling

- `mix precommit` runs the same sequence as GitHub CI (deps.get, deps.compile, unused-dependency check, compile with `--warnings-as-errors`, test suite with warnings treated as errors, formatter check, Credo, Sobelow, deps.audit, hex.audit, Dialyzer, and docs generation with warnings as errors) so it should be used locally before opening a PR.

## Testing Practices

- Unit tests MUST be deterministic. A test must either pass or fail consistently, not accept both outcomes.
- Never call `Process.sleep/1` in tests; prefer synchronization helpers so suites stay deterministic.
- Keep unit tests in `test/ash_agent`, mirroring `lib/` structure with `<filename>_test.exs`, and default to `async: true` when isolation is possible.

## Test Organization

### Directory Structure

Tests are organized by **feature first**, then backend, then provider. This makes it easy to see test coverage at a glance.

```
test/
├── ash_agent/           # Unit tests (mirror lib/ structure)
├── integration/          # Integration tests (by feature > backend > provider)
│   ├── metadata/         # Metadata extraction tests
│   │   ├── req_llm/
│   │   │   ├── openai_test.exs
│   │   │   ├── anthropic_test.exs
│   │   │   └── ollama_test.exs
│   │   └── baml/
│   │       ├── openai_test.exs
│   │       └── anthropic_test.exs
│   ├── thinking/         # Extended thinking tests
│   │   ├── req_llm/
│   │   │   └── anthropic_test.exs
│   │   └── baml/
│   │       └── anthropic_test.exs
│   ├── agentic_loop/     # Agentic loop tests
│   │   └── ...
│   └── stub/             # Tests using mocked providers
│       └── basic_test.exs
└── support/              # Test helpers
    ├── integration_case.ex
    └── stubs/
```

### Running Tests

```bash
# Unit tests only (default)
mix test

# All integration tests
mix test.integration

# By backend
mix test.integration --only backend:req_llm
mix test.integration --only backend:baml

# By provider
mix test.integration --only provider:openai
mix test.integration --only provider:anthropic
mix test.integration --only provider:ollama

# Combine filters
mix test.integration --only backend:baml --only provider:anthropic

# Exclude
mix test.integration --exclude provider:openai
```

### Required Environment Variables

| Provider | Env Var | Notes |
|----------|---------|-------|
| openai | `OPENAI_API_KEY` | |
| anthropic | `ANTHROPIC_API_KEY` | |
| openrouter | `OPENROUTER_API_KEY` | |
| ollama | (none) | Local service |

### Writing Integration Tests

```elixir
# Feature > Backend > Provider naming: metadata/req_llm/openai_test.exs
defmodule AshAgent.Integration.Metadata.ReqLLM.OpenAITest do
  use AshAgent.IntegrationCase, backend: :req_llm, provider: :openai

  test "extracts token usage" do
    # API key is validated before this runs
  end
end
```

## Reference Reading

- https://www.anthropic.com/engineering/building-effective-agents
