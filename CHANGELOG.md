# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Add provider metadata extraction for session persistence

### Fixed

- Fix compile-time struct expansion for optional ash_baml dependency

## [0.3.0] - 2024-11-29

### Changed

- **BREAKING**: Replace `input` block and `output` with `input_schema` and `output_schema` using Zoi schemas
- **BREAKING**: Replace `prompt` with `instruction` DSL
- Add context builder pattern with `context/1`, `instruction/1`, `user/1` functions

### Added

- Add documentation for agentic loop patterns using `Zoi.union` for discriminated outputs

## [0.2.0] - 2024-11-27

### Added

- Add `AshAgent.Result` wrapper for call/stream responses with thinking, usage, and metadata
- Add BAML provider thinking extraction via `AshBaml.Response.thinking/1`
- Add integration tests for extended thinking capabilities

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
