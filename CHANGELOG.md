# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2024-11-26

### Added

- Initial release
- Declarative agent DSL via `AshAgent.Resource` and `AshAgent.Domain` extensions
- Auto-generated `:call` and `:stream` actions for agent invocation
- Provider abstraction with built-in support for `:req_llm` and `:baml`
- Liquid template prompts with `~p` sigil for compile-time validation
- Hook system for customizing agent behavior (`before_call`, `after_render`, `after_call`, `on_error`)
- Telemetry events for `[:ash_agent, :call]`, `[:ash_agent, :stream]`, `[:ash_agent, :llm]`, and `[:ash_agent, :prompt]`
- TypedStruct output types with automatic JSON Schema conversion
