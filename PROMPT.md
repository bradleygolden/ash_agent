# AshAgent: Complete Declarative AI Agent Framework Implementation

## Context

Phase 0 (Foundation) is COMPLETE! ✅

Now continue implementing the full vision: Transform AshAgent into a comprehensive, **provider-agnostic** declarative AI agent framework for the Ash ecosystem.

## CRITICAL ARCHITECTURE PRINCIPLE: PROVIDER AGNOSTIC

**This framework MUST remain provider-agnostic throughout ALL phases:**

- ❌ Do NOT hardcode dependencies on specific LLM libraries (ReqLLM, etc.)
- ✅ The framework is an **orchestration layer** - NOT an LLM execution layer
- ✅ Define behaviors/protocols (like Ash.Resource) that allow multiple implementations
- ✅ Users can choose their LLM library: **ash_baml**, **req_llm**, **langchain**, or custom implementations
- ✅ Framework handles: orchestration, state, workflows, memory, tools - NOT direct LLM calls
- ✅ Think: **Broadway is to data processing as AshAgent is to AI agents**

### How to Maintain Provider Agnostic Design

1. **Use behaviors/protocols** for LLM interaction points
2. **Delegate execution** to user-provided or configured providers
3. **Test with BOTH** ash_baml AND req_llm to ensure compatibility
4. **Document provider patterns** so users can plug in their own
5. **Keep the Runtime agnostic** - let providers handle specifics

## Phase 0 Status ✅

**Completed:**
- Architecture documentation
- Runtime refactoring (PromptRenderer, LLMClient, Hooks, Error handling)
- Enhanced SchemaConverter (nested types, unions)
- Comprehensive test suite (52 tests, 76-80% coverage)
- 10 clean commits, zero warnings

**Current state:**
- Solid foundation with extensibility hooks
- Clean separation of concerns
- Backward compatible
- Ready for next phases

## Your Task: Complete Phases 1-6

Work through the remaining phases from the full implementation plan. Reference:
- **Full Plan**: `.springfield/11-06-2025-declarative-ai-agent-framework/plan-v1.md`
- **Skinner's Review**: `.springfield/11-06-2025-declarative-ai-agent-framework/review.md`
- **Phase 0 Completion**: `.springfield/11-06-2025-declarative-ai-agent-framework/completion.md`

### Remaining Phases

#### Phase 1: Tool & Function Calling (Priority: HIGH)
**Duration**: 4-5 weeks

**Key Requirements**:
- Declarative tool definitions using Ash DSL
- Automatic tool schema generation
- Provider-agnostic tool execution (works with both ash_baml and req_llm)
- Multi-turn tool calling support
- Tool result handling and validation

**Provider Agnostic Approach**:
- Define tool schema as Ash entities
- Let providers (ash_baml/req_llm) handle LLM function calling
- Framework manages tool registration, validation, execution orchestration

#### Phase 2: Memory & State Management (Priority: HIGH)
**Duration**: 3-4 weeks

**Key Requirements**:
- Conversation history management
- Context window handling
- State persistence (optional)
- Memory strategies (sliding window, summarization)

**Provider Agnostic Approach**:
- Memory layer is independent of LLM provider
- Works the same whether using ash_baml or req_llm
- Pluggable storage backends

#### Phase 3: Workflow Patterns (Priority: MEDIUM)
**Duration**: 3-4 weeks

**Key Requirements**:
- Sequential workflows
- Parallel execution
- Conditional branching
- Error recovery and retry patterns
- Workflow state machines

**Provider Agnostic Approach**:
- Workflows orchestrate agent calls, not LLM calls
- Works with any provider implementation
- Framework manages flow control, providers handle generation

#### Phase 4: Multi-Agent Orchestration (Priority: MEDIUM)
**Duration**: 4-5 weeks

**Key Requirements**:
- Agent-to-agent communication
- Hierarchical agent structures
- Collaborative workflows
- Agent supervision trees

**Provider Agnostic Approach**:
- Each agent can use different providers
- Communication layer is provider-independent
- Supervision handles agent failures, not LLM failures

#### Phase 5: Production Hardening (Priority: HIGH)
**Duration**: 3-4 weeks

**Key Requirements**:
- Rate limiting
- Cost tracking
- Comprehensive telemetry
- Human-in-the-loop support
- Caching strategies

**Provider Agnostic Approach**:
- Telemetry wraps provider calls
- Cost tracking via provider adapters
- Rate limiting at framework level

#### Phase 6: Documentation & Polish (Priority: HIGH)
**Duration**: 2-3 weeks

**Key Requirements**:
- Complete guides for both ash_baml AND req_llm
- Example applications showing both providers
- Migration guides
- Best practices documentation
- Igniter templates

## Implementation Strategy

### Start Simple, Build Incrementally
Follow Anthropic's guidance: Start with simple workflows before adding complex agentic behavior.

### Work in Small Iterations
- One feature at a time
- Test after each change
- Commit frequently with clear messages
- Keep backward compatibility

### Provider Agnostic Testing
For each phase, create tests that verify:
1. Works with ash_baml
2. Works with req_llm
3. Works with a mock provider
4. Provider can be swapped without code changes

### Quality Standards
- Zero compiler warnings
- Zero Credo issues
- Test coverage > 80%
- All tests passing
- Idiomatic Elixir/Ash code

## Important Files

**Reference Materials**:
- Full plan: `.springfield/11-06-2025-declarative-ai-agent-framework/plan-v1.md`
- Research: `.springfield/11-06-2025-declarative-ai-agent-framework/research.md`
- Review feedback: `.springfield/11-06-2025-declarative-ai-agent-framework/review.md`
- Phase 0 completion: `.springfield/11-06-2025-declarative-ai-agent-framework/completion.md`

**External References**:
- ash_baml: `/Users/bradleygolden/Development/bradleygolden/ash_baml` (or https://github.com/bradleygolden/ash_baml)
- Anthropic principles: https://www.anthropic.com/engineering/building-effective-agents
- Effective context: https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
- Multi-agent systems: https://www.anthropic.com/engineering/multi-agent-research-system

## Success Criteria

The implementation is complete when:

### Functional Requirements
- ✅ All 6 phases implemented
- ✅ Works seamlessly with ash_baml
- ✅ Works seamlessly with req_llm
- ✅ Users can plug in custom providers
- ✅ Framework is truly provider-agnostic

### Quality Requirements
- ✅ Comprehensive test suite (>80% coverage)
- ✅ Zero warnings (compiler, Credo, Dialyzer)
- ✅ Complete documentation with examples for both providers
- ✅ Example applications demonstrating key features
- ✅ Migration guides for existing users

### Architecture Requirements
- ✅ Clean separation: orchestration vs execution
- ✅ Extensible via hooks and behaviors
- ✅ Idiomatic to Ash Framework
- ✅ BEAM-native concurrency and fault tolerance

## Getting Started

1. Read Phase 0 completion summary
2. Review full plan-v1.md to understand all phases
3. Start with Phase 1 (Tools & Function Calling)
4. Work incrementally, test with BOTH ash_baml and req_llm
5. Commit frequently
6. Move to next phase when current phase is solid

## Remember

- **Provider agnostic**: Test with ash_baml AND req_llm throughout
- **Start simple**: Don't over-engineer, build incrementally
- **Escape hatches**: Always provide low-level access when needed
- **Idiomatic Ash**: Follow Ash patterns and conventions
- **Quality over speed**: Take time to do it right

Let's build the best declarative AI agent framework for Elixir! 🚀
