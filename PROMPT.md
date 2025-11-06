springfield help me turn this project into a full-fledged declarative AI agent framework.

## Core Architecture Principle: PROVIDER AGNOSTIC

**CRITICAL**: This framework MUST be provider-agnostic and serve as an orchestration layer, NOT an LLM execution layer.

- ❌ Do NOT require specific LLM libraries (ReqLLM, etc.)
- ❌ Do NOT lock into specific providers
- ✅ Define behaviors/protocols (like Ash.Resource) that allow multiple implementations
- ✅ Users choose their LLM library: ash_baml, req_llm, langchain, or custom implementations
- ✅ Framework handles orchestration, state, workflows, memory - NOT direct LLM calls
- ✅ Think: Broadway is to data processing as AshAgent is to AI agents

## Vision

Create a declarative AI agent framework inspired by popular frameworks (LangChain, LangGraph, CrewAI, AutoGen) but designed idiomatically for Ash Framework. Think of successful patterns from other AI frameworks and port those ideas to work naturally with Ash's declarative philosophy.

Existing changes in the project are outdated - feel free to modify/delete files as needed to create the right foundation.

## Key Requirements

### 1. Flexibility & Escape Hatches
Like ash_baml, provide multiple levels of control:
- **High-level**: Quick prototyping, simple use cases (declarative DSL)
- **Mid-level**: Standard workflows with moderate control
- **Low-level**: Full control when needed (e.g., chat interfaces requiring precise behavior)

Users should be able to tap into underlying implementation details when necessary.

### 2. Idiomatic Ash Design
- Follow Ash Framework patterns and conventions
- Leverage Ash's DSL capabilities
- Think about how other Elixir projects handle extensibility
- Use Ash's extension system where appropriate

### 3. Research-Driven
Use the hex skill and usage-rules skill to research:
- Popular declarative AI agent frameworks with wide adoption
- Successful patterns people find useful
- Integration patterns within the Ash/Elixir ecosystem

Sources:
- https://www.anthropic.com/engineering/building-effective-agents
- https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
- https://www.anthropic.com/engineering/multi-agent-research-system
- /Users/bradleygolden/Development/bradleygolden/ash_baml (ash_baml - or https://github.com/bradleygolden/ash_baml, it's not on hex yet)
