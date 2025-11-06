# Implementation Task: AshAgent - Declarative AI Agent Framework (Phase 0: Foundation)

## Context

You are implementing the foundational phase of transforming AshAgent into a comprehensive, declarative AI agent framework for the Ash ecosystem. This project draws inspiration from successful frameworks like LangChain, CrewAI, and LangGraph, while maintaining Ash's declarative philosophy and leveraging BEAM's unique strengths.

**Critical Principle**: Start simple. Anthropic research emphasizes beginning with workflows before adding agentic behavior. We'll build progressively from a solid foundation.

## What You're Building

Transform AshAgent from a basic LLM integration into a flexible, production-ready agent framework with:
- Simple, declarative DSL for quick prototyping
- Escape hatches for advanced control (following ash_baml pattern)
- Idiomatic Ash patterns throughout
- BEAM-native concurrency and fault tolerance

## Your Task: Phase 0 - Foundation (Start Here)

Based on Principal Skinner's review and Anthropic's "start simple" guidance, **focus on Phase 0 only**. This establishes the foundation for everything else.

### Objectives

1. **Audit & Document**: Understand current architecture deeply
2. **Refactor Runtime**: Make it extensible with hooks and better error handling
3. **Enhance SchemaConverter**: Support complex types (unions, nested arrays, discriminated unions)
4. **Test Infrastructure**: Comprehensive unit + integration tests
5. **Telemetry**: Instrument existing operations
6. **Documentation**: Developer-friendly docs using Spark
7. **~~Benchmarking~~**: **SKIP THIS TASK** - Not needed for Phase 0

### Implementation Details

#### Task 0.1: Audit Current Architecture

**File**: Create `documentation/topics/architecture.md`

Document:
- Current module structure and responsibilities
- Data flow through the system
- Extension points and limitations
- Dependencies and their purposes

Use `Read` tool to examine:
- `lib/ash_agent.ex`
- `lib/ash_agent/resource.ex`
- `lib/ash_agent/domain.ex`
- `lib/ash_agent/runtime.ex`
- `lib/ash_agent/dsl.ex`
- `lib/ash_agent/schema_converter.ex`

#### Task 0.2: Refactor Runtime for Extensibility

**File**: `lib/ash_agent/runtime.ex`

Current implementation is monolithic. Refactor to:

1. **Extract concerns**:
   - Prompt rendering → `AshAgent.Runtime.PromptRenderer`
   - Schema conversion → keep in `SchemaConverter`
   - LLM interaction → `AshAgent.Runtime.LLMClient`

2. **Add hook system**:
   ```elixir
   defmodule AshAgent.Runtime.Hooks do
     @type hook_context :: %{
       agent: module(),
       input: map(),
       rendered_prompt: String.t() | nil,
       response: any() | nil
     }

     @callback before_call(hook_context()) :: {:ok, hook_context()} | {:error, term()}
     @callback after_call(hook_context()) :: {:ok, hook_context()} | {:error, term()}
   end
   ```

3. **Improve error handling**:
   - Wrap all external calls in try/catch
   - Return structured errors: `{:error, %AshAgent.Error{type: :llm_error, message: ...}}`
   - Add retry logic with exponential backoff (simple version)

4. **Keep it backward compatible**: All changes must not break existing code

#### Task 0.3: Enhance SchemaConverter

**File**: `lib/ash_agent/schema_converter.ex`

Add support for:

1. **Union types**: `AshBaml.Type.Union`
2. **Discriminated unions**: Tagged unions with type field
3. **Nested arrays**: `{:array, {:array, :string}}`
4. **Optional fields**: Proper handling of `allow_nil?: true`
5. **Custom types**: Extension point for user-defined types

Test with ash_baml examples to ensure compatibility.

#### Task 0.4: Comprehensive Test Suite

**Files**: `test/ash_agent/*_test.exs`

Create:
- `test/ash_agent/runtime_test.exs` - Unit tests for runtime operations
- `test/ash_agent/schema_converter_test.exs` - All type conversions
- `test/ash_agent/integration_test.exs` - End-to-end flows
- `test/support/test_agents.ex` - Reusable test agent definitions

Use ExUnit best practices:
- Descriptive test names
- Setup blocks for common test data
- doctests where appropriate
- Property-based tests for schema conversion (use StreamData)

#### Task 0.5: Add Telemetry

**Integration**: Throughout runtime operations

Add telemetry events for:
- `[:ash_agent, :call, :start]` - Before LLM call
- `[:ash_agent, :call, :stop]` - After successful LLM call
- `[:ash_agent, :call, :exception]` - On error
- `[:ash_agent, :stream, :start]` - Before streaming
- `[:ash_agent, :stream, :stop]` - After streaming completes
- `[:ash_agent, :stream, :exception]` - On streaming error

Include metadata:
- Agent module
- Model used
- Token counts (if available)
- Duration
- Input/output sizes

Reference: `:telemetry` library patterns

#### Task 0.6: Developer Documentation

**Files**:
- `documentation/topics/architecture.md` - System architecture
- `documentation/dsls/AshAgent.Resource.md` - Update with latest DSL
- `documentation/dsls/AshAgent.Domain.md` - Domain extension docs
- `documentation/topics/testing.md` - How to test agents

Use Spark's documentation features. Ensure all DSL options are documented with examples.

#### Task 0.7: Benchmarking Infrastructure **[SKIP - NOT REQUIRED]**

~~This task has been skipped per user request. Benchmarking can be added later if needed.~~

### Implementation Strategy

1. **Work incrementally**: One task at a time, commit after each
2. **Test as you go**: Write tests before or alongside implementation
3. **Document decisions**: Add comments explaining "why" not just "what"
4. **Stay idiomatic**: Follow Ash patterns (look at Ash core for examples)
5. **No premature optimization**: Focus on correctness and clarity first

### Success Criteria

Phase 0 is complete when:
- [ ] All existing functionality still works (backward compatible)
- [ ] Test coverage > 80%
- [ ] Documentation is comprehensive and accurate
- [ ] Telemetry events are firing correctly
- [ ] ~~Benchmarks establish baselines~~ **[SKIPPED]**
- [ ] Code follows Elixir/Ash idioms
- [ ] No compiler warnings or Credo issues

### Important Constraints

1. **No new dependencies** in Phase 0 unless absolutely necessary
2. **Maintain backward compatibility**: Existing users must not break
3. **Follow CLAUDE.md guidelines**: No @spec unless needed, no unnecessary comments
4. **Use existing patterns**: Look at ash_baml for escape hatch patterns
5. **Keep it simple**: Resist adding "nice to have" features

### After Phase 0

Once Phase 0 is solid, we'll proceed to:
- Phase 1: Tool & Function Calling
- Phase 2: Memory & State Management
- Phase 3: Workflow Patterns
- Phase 4: Multi-Agent Orchestration
- Phase 5: Production Hardening

But that's for later. **Focus on the foundation first.**

### Resources

- Research: `.springfield/11-06-2025-declarative-ai-agent-framework/research.md`
- Full Plan: `.springfield/11-06-2025-declarative-ai-agent-framework/plan-v1.md`
- Review Feedback: `.springfield/11-06-2025-declarative-ai-agent-framework/review.md`
- Anthropic Principles: https://www.anthropic.com/engineering/building-effective-agents
- ash_baml: `/Users/bradleygolden/Development/bradleygolden/ash_baml`

### Getting Started

1. Read and understand the current codebase (Task 0.1)
2. Create a feature branch: `git checkout -b feature/phase-0-foundation`
3. Work through tasks 0.2-0.6 sequentially (skip 0.7)
4. Commit frequently with clear messages (imperative mood)
5. Run tests and quality checks regularly
6. When complete, create a summary of what was accomplished

Remember: **Start simple, build incrementally, maintain quality**. This foundation will support everything that comes after.

Good luck! 🚀
