# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Initial project setup as Ash extension library
- `AshAgent.Resource` extension for adding agent capabilities to resources
- `AshAgent.Domain` extension for domain-level agent configuration
- `AshAgent.Info` module for introspection
- Basic DSL sections for agent configuration
- Comprehensive documentation structure
- Mix project configuration for Hex publishing

#### Progressive Disclosure Features

##### Result Processors
- `AshAgent.ResultProcessors.Truncate` - Truncate large tool results with UTF-8 safe handling
- `AshAgent.ResultProcessors.Summarize` - Summarize results with rule-based heuristics
- `AshAgent.ResultProcessors.Sample` - Sample items from list results with configurable strategies
- `AshAgent.ResultProcessor` behavior - Contract for implementing custom result processors
- Shared utilities in `AshAgent.ResultProcessors` for size estimation and structure preservation

##### Context Helpers
- `AshAgent.Context.keep_last_iterations/2` - Sliding window iteration management
- `AshAgent.Context.remove_old_iterations/2` - Remove iterations older than specified age
- `AshAgent.Context.count_iterations/1` - Get iteration count
- `AshAgent.Context.get_iteration_range/3` - Extract iteration slice by index range
- `AshAgent.Context.mark_as_summarized/2` - Mark iteration as summarized with summary text
- `AshAgent.Context.is_summarized?/1` - Check if iteration has been summarized
- `AshAgent.Context.get_summary/1` - Retrieve summary from summarized iteration
- `AshAgent.Context.update_iteration_metadata/3` - Update custom metadata on iterations
- `AshAgent.Context.exceeds_token_budget?/2` - Check if context exceeds token budget
- `AshAgent.Context.estimate_token_count/1` - Fast token count estimation (~4 chars/token heuristic)
- `AshAgent.Context.tokens_remaining/2` - Calculate remaining tokens before budget limit
- `AshAgent.Context.budget_utilization/2` - Calculate budget utilization as percentage

##### High-Level Utilities
- `AshAgent.ProgressiveDisclosure.process_tool_results/2` - Processor composition pipeline with configurable truncate/summarize/sample options
- `AshAgent.ProgressiveDisclosure.sliding_window_compact/2` - Sliding window context compaction strategy
- `AshAgent.ProgressiveDisclosure.token_based_compact/2` - Token budget-based context compaction strategy

##### Documentation
- Comprehensive Progressive Disclosure guide (`documentation/guides/progressive-disclosure.md`)
- Example application demonstrating 70% token savings (`examples/progressive_disclosure_demo/`)
- README section with Progressive Disclosure quick start
- API documentation with 25 doctests across all PD modules
- Cookbook patterns for common PD use cases
- Troubleshooting guide for PD-related issues

##### Testing
- Unit tests for all result processors (Truncate, Summarize, Sample) with 90%+ coverage
- Unit tests for Context helper functions covering iteration, metadata, and token management
- Unit tests for ProgressiveDisclosure module covering pipelines and compaction strategies
- Integration tests demonstrating end-to-end workflows:
  - Tool result truncation via hooks
  - Context compaction with sliding window
  - Token budget enforcement
  - Processor composition and determinism
- 25 doctests covering all public APIs
- Example application integration tests

### Changed
- N/A

### Deprecated
- N/A

### Removed
- N/A

### Fixed
- N/A

### Security
- N/A

## [0.1.0] - TBD

- Initial release (not yet published)

[Unreleased]: https://github.com/bradleygolden/ash_agent/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/bradleygolden/ash_agent/releases/tag/v0.1.0
