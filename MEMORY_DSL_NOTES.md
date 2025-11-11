# Memory DSL Brainstorm

## Context
- `AshAgent.Transformers.AddContextAttribute` injects an `AshAgent.Context` attribute onto every agent resource, so conversation history already persists alongside resource records.
- `AshAgent.Context` stores iterations, messages, tool calls, and metadata; runtime hooks (`prepare_context`, `prepare_messages`, etc.) hand this struct around each tool-calling turn.
- Progressive Disclosure utilities (`AshAgent.ProgressiveDisclosure`) already implement sliding windows, token-budget trimming, truncation, and summarization routines that operate directly on the context and tool results.

## Full DSL Concept
- **Stores**: Declarative `buffer`, `summary`, `knowledge`, etc., blocks that describe how to derive curated views from `AshAgent.Context` (e.g., keep last _n_ iterations, filter by role, run scheduled summaries, persist facts via adapters).
- **Pipelines**: Deterministic `pipeline` blocks that `select` named stores, optionally `summarize` or `weight` them, and `inject` the rendered result into prompt assembly or tool message preparation.
- **Hooks Integration**: Generated config drives existing hooks—buffers run inside `prepare_context`, summaries can hook into `prepare_tool_results` / `on_iteration_complete`, and pipelines shape the payload right before `prepare_messages` hands it to the provider.
- **Domain Overrides**: `AshAgent.Domain` could host a `memory` section so teams define org-wide defaults (e.g., sliding window size) and agents override only what's different.

## Simplified MVP (80–90% Coverage)
To land quickly while honoring Anthropic's context-engineering advice, we can narrow the initial DSL scope:

1. **Single `buffer` entity** per agent (or fall back to `:full_history`). Schema includes `window` and optional `roles`. Runtime simply applies sliding-window trimming + role filtering to `AshAgent.Context` before each turn.
2. **Optional `summary` entity** tied to that buffer. Schema covers `refresher` module, `refresh_every` iterations, optional `inject` location. Runtime invokes the refresher, stores the summary in context metadata, and prepends/appends it when injecting messages.
3. **Implicit pipeline**: No separate `pipeline` block initially. The runtime automatically injects the trimmed buffer plus the optional summary into the prompt (configurable insertion point such as `:system` vs `:prompt_prefix`).

This MVP keeps the DSL tiny, aligns with existing Spark patterns, and still supports the majority of practical needs: bounded history, lightweight summaries, and predictable prompt shaping.

## Example (MVP Shape)
```elixir
agent do
  memory do
    buffer :recent_messages,
      window: 8,
      roles: [:user, :assistant]

    summary :working_plan,
      source: :recent_messages,
      refresher: MyApp.Memory.PlanSummarizer,
      refresh_every: 3,
      inject: :prompt_prefix
  end
end
```

Runtime flow:
1. Trim `AshAgent.Context` to the last eight user/assistant turns before rendering messages.
2. Every three iterations, call `PlanSummarizer` with the same buffer, store the summary on the context, and inject it ahead of the prompt body.
3. If no `summary` is defined, only the trimmed buffer is injected; if no `memory` block exists, behavior stays identical to today's full-history prompt.

## Next Steps
1. Define `memory` section schema (buffer + summary entities) in `AshAgent.DSL` and expose it via `AshAgent.Resource` (and optionally `AshAgent.Domain`).
2. Extend the runtime to materialize configured buffers/summaries using the existing Progressive Disclosure helpers before each LLM call.
3. Iterate towards richer features (multiple buffers, explicit pipelines, external knowledge adapters) once the MVP pattern is validated.
