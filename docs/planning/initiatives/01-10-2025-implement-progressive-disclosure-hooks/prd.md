---
type: concept
id: progressive-disclosure-hooks-prd
title: Progressive Disclosure Hook System - Product Requirements Document
audience: engineering
status: approved
complexity: complex
priority: high
version: 1.0
created: 2025-01-10
updated: 2025-01-10
author: Martin Prince
reviewers:
  - Lisa Simpson (Research)
  - Mayor Quimby (Complexity Assessment)
  - Professor Frink (Implementation Plan)
  - Principal Skinner (Standards Review)
schema: concept.xsd
---

# Progressive Disclosure Hook System - Product Requirements Document

**Prepared By:** Martin Prince, A+ Student and Documentation Specialist
**Date:** January 10, 2025
**Status:** ✅ APPROVED FOR IMPLEMENTATION
**Complexity:** COMPLEX (affects 10+ files, architectural changes)
**Estimated Duration:** 3 weeks (77 subtasks)

*"I've prepared a comprehensive and impeccable product requirements document that will earn an A+ from any review committee!"*

---

## Executive Summary

This PRD specifies the implementation of a comprehensive hook system for Progressive Disclosure in AshAgent. According to my thorough analysis of Lisa Simpson's research (which was excellent, though I would have organized it differently), this system will extend the existing `AshAgent.Runtime.Hooks` behavior with five new data-level callbacks that enable context compaction, tool result summarization, and custom workflow control.

**Critical Achievement:** This implementation maintains 100% backwards compatibility while enabling sophisticated Progressive Disclosure patterns identified in the AshAgent roadmap.

### Key Deliverables

1. **Extended Hook Behavior** - 5 new callbacks in Runtime.Hooks
2. **Runtime Integration** - Hook execution at 5 integration points
3. **DefaultHooks Module** - Refactored token tracking and max iterations
4. **Comprehensive Testing** - Unit, integration, and compatibility tests
5. **Complete Documentation** - API docs, examples, and patterns

### Success Criteria

✅ All tests pass (`mix test`)
✅ Full CI passes (`mix check`)
✅ Zero breaking changes proven
✅ Progressive Disclosure features enabled
✅ Performance overhead < 1% per iteration
✅ Complete documentation with examples

---

## Background and Context

### Research Foundation

This project builds on comprehensive validation work by Lisa Simpson across four research sessions that validated integration points at exact line numbers, confirmed the hook pattern is extensible, and identified 5 pieces of existing code that would benefit from hooks.

**Complexity Assessment:** Mayor Quimby declared this COMPLEX based on affecting 10+ files, introducing new architectural patterns, requiring refactoring of hardcoded logic, and needing comprehensive testing.

**Implementation Planning:** Professor Frink created a detailed 77-subtask implementation plan, reviewed and approved by Principal Skinner.

### Current State

The existing `AshAgent.Runtime.Hooks` provides four operation-level hooks (before_call, after_render, after_call, on_error) but lacks data-level hooks for tool results, context, or messages. Token tracking (runtime.ex:225-264) and max iterations (runtime.ex:174-180) are currently hardcoded.

---

## Problem Statement

**Problem 1:** No hook to process tool results before adding to context
**Problem 2:** No hook to compact context before message conversion
**Problem 3:** No hook to transform messages before LLM call
**Problem 4:** Hardcoded max iterations with no customization
**Problem 5:** Hardcoded token tracking with no customization

---

## Goals and Objectives

**Primary Goals:**
- Enable Progressive Disclosure (P0)
- Maintain backwards compatibility (P0)
- Refactor hardcoded logic to hooks (P0)

**Secondary Goals:**
- Comprehensive testing (P1)
- Complete documentation (P1)
- Minimal performance impact (P2)

---

## Functional Requirements

### FR-1: Extend Runtime.Hooks Behavior

Add five new callbacks with proper typespecs:

```elixir
@callback prepare_tool_results(tool_result_context()) :: {:ok, tool_result_context()} | {:error, term()}
@callback prepare_context(context_preparation_context()) :: {:ok, context_preparation_context()} | {:error, term()}
@callback prepare_messages(message_context()) :: {:ok, message_context()} | {:error, term()}
@callback on_iteration_start(iteration_context()) :: {:ok, iteration_context()} | {:error, term()}
@callback on_iteration_complete(iteration_context()) :: {:ok, iteration_context()} | {:error, term()}
```

### FR-2: Integrate Hook Execution Points

**Point 1:** runtime.ex:274-281 - prepare_tool_results (after tool execution)
**Point 2:** runtime.ex:183 - prepare_context (before Context.to_messages)
**Point 3:** runtime.ex:183 - prepare_messages (after Context.to_messages)
**Point 4:** runtime.ex:174-180 - on_iteration_start (loop start)
**Point 5:** runtime.ex:180 - on_iteration_complete (after iteration)

### FR-3: Create DefaultHooks Module

Refactor token tracking and max iterations into DefaultHooks.on_iteration_start and DefaultHooks.on_iteration_complete. Use fallback pattern: DefaultHooks execute when no custom hooks configured.

### FR-4: Add Type Definitions

Define tool_result_context, context_preparation_context, message_context, and iteration_context with all required fields.

### FR-5: Implement Error Handling Strategy

- prepare_* hooks: Fallback to original data on error
- on_iteration_start: Abort iteration on error
- on_iteration_complete: Log and continue on error

---

## Technical Requirements

### TR-1: Code Quality Standards

Per AGENTS.md: NO new inline comments (use @moduledoc/@doc only), AVOID @spec unless necessary, imperative mood commits.

### TR-2: Testing Standards

Deterministic tests, NO Process.sleep, use LLMStub, pattern matching assertions, async: true for unit tests, @moduletag :integration for integration tests.

### TR-3: CI/CD Compliance

Must pass: compilation, tests, format check, credo, dialyzer, documentation generation.

### TR-4: Performance Requirements

Hook dispatch overhead < 1% per iteration (measured via baseline comparison).

### TR-5: Telemetry Requirements

Emit [:ash_agent, :hook, :start], [:ash_agent, :hook, :stop], and [:ash_agent, :hook, :error] events.

---

## Implementation Strategy

### Three-Phase Plan (77 Subtasks)

**Phase 1 (Week 1):** Hook System Extension
- Extend Runtime.Hooks with 5 callbacks (subtasks 1-8)
- Add type definitions (subtasks 9-14)
- Write unit tests (subtasks 15-22)

**Phase 2 (Week 2):** Runtime Integration & Refactoring
- Add hook helpers (subtasks 23-28)
- Integrate 5 hooks in runtime.ex (subtasks 29-38)
- Create DefaultHooks module (subtasks 39-47)

**Phase 3 (Week 3):** Testing & Documentation
- Integration tests (subtasks 48-55)
- Backwards compatibility tests (subtasks 56-61)
- Documentation (subtasks 62-68)
- Validation (subtasks 69-77)

---

## Testing Requirements

**Unit Tests:** Test each hook in isolation with mock implementations
**Integration Tests:** Test Progressive Disclosure workflows with LLMStub
**Backwards Compatibility Tests:** Prove agents without hooks work unchanged

---

## Success Metrics

Implementation complete when all 77 subtasks finished, mix check passes, tests deterministic, performance acceptable, documentation complete, zero breaking changes proven.

---

## Risk Assessment

Overall risk: LOW
Confidence: 87% (Skinner-approved)

Risks mitigated via comprehensive documentation, careful testing, backwards compatibility guarantees, and multiple validation checkpoints.

---

## Timeline

**Week 1:** January 13-17 (Extension)
**Week 2:** January 20-24 (Integration)
**Week 3:** January 27-31 (Testing & Docs)

Four validation checkpoints at phase boundaries.

---

## Dependencies

Internal: Runtime.Hooks, Context, Runtime, ToolExecutor, LLMClient, Error, TokenLimits (all stable)
External: No new dependencies required
Overall dependency risk: LOW

---

## References

- Lisa Simpson's 4 research sessions (.springfield/)
- Mayor Quimby's complexity assessment
- Professor Frink's 77-subtask plan
- Principal Skinner's standards review
- AGENTS.md compliance requirements
- README.md roadmap (line 106)

---

## Conclusion

This PRD specifies a comprehensive implementation that enables roadmap features, maintains backwards compatibility, follows best practices, meets quality standards, and manages risk effectively.

**Implementation Confidence:** 87% (Skinner-approved)
**Recommendation:** APPROVE FOR IMPLEMENTATION

*"I've earned an A+ on this PRD! It's comprehensive, precise, and follows all academic standards!"*

---

**Martin Prince**
*A+ Student and Documentation Specialist*
*Springfield Elementary School*
*January 10, 2025*

**Approved By:**
- Lisa Simpson (Research Lead)
- Mayor Quimby (Complexity Assessment)
- Professor Frink (Implementation Planning)
- Principal Skinner (Standards and Compliance)

**Status:** ✅ APPROVED FOR IMPLEMENTATION
**Next Step:** Ralph begins autonomous implementation loop
