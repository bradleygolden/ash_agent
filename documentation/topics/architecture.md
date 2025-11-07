# AshAgent Architecture

## Overview

AshAgent is an Ash Framework extension that enables declarative AI agent development using Spark DSL. The library transforms agent definitions into executable Ash actions with type-safe inputs/outputs.

## Module Structure

### Core Modules

#### `AshAgent`
Main module providing package-level documentation and entry point. Minimal functionality - primarily serves as documentation hub.

#### `AshAgent.Resource`
Spark DSL extension for Ash resources. Makes any Ash resource "agent-aware" by:
- Adding the `agent` DSL section
- Registering transformers that validate configuration and generate actions
- Importing the `~p` sigil for prompt templates

**Key responsibilities:**
- Extension registration with Spark
- DSL section definition
- Transformer pipeline setup

**Extension points:**
- Transformers can be added/modified
- DSL sections can be extended

#### `AshAgent.Domain`
Spark DSL extension for Ash domains. Currently minimal - provides domain-level `agent` section for future global configuration.

**Current state:** Placeholder for future domain-level settings
**Future potential:** Default clients, shared prompt fragments, domain-wide policies

#### `AshAgent.Runtime`
The execution engine. Orchestrates the entire agent call lifecycle.

**Data flow:**
1. `call/2` or `stream/2` entry points
2. `get_agent_config/1` - Read DSL configuration via Spark.Dsl.Extension
3. `render_prompt/2` - Process Liquid templates with Solid
4. `build_schema/1` - Convert TypedStruct to req_llm schema
5. `generate_object/3` or `stream_object/3` - Call ReqLLM
6. `build_result/2` - Parse JSON response into TypedStruct

**Key characteristics:**
- Monolithic (all concerns in one module)
- Uses `with` pipelines for error handling
- Minimal error recovery
- Direct ReqLLM integration

**Limitations:**
- No hooks for customization
- Limited error context
- Hard to test individual components
- No retry or fallback logic

#### `AshAgent.DSL`
DSL definitions using Spark primitives.

**Structure:**
- `Argument` entity for input arguments
- `input` section containing argument entities
- `agent` section as top-level configuration
- `client/2` macro for ergonomic client definition

**Schema validation:**
- Client config validated via custom function
- Type constraints on all options
- Required vs optional field enforcement

#### `AshAgent.SchemaConverter`
Transforms TypedStruct field definitions into req_llm schema format.

**Mapping logic:**
- Reads Ash.TypedStruct.Field structs
- Maps Ash types to req_llm types (`:string`, `:integer`, etc.)
- Handles arrays recursively
- Detects nested TypedStructs (`:object` type)
- Falls back to `:any` for unknown types

**Current support:**
- Primitive types (string, integer, float, boolean, map)
- Arrays of primitives
- Nested TypedStructs
- Optional vs required fields

**Missing support:**
- Union types
- Discriminated unions
- Nested arrays (array of arrays)
- Custom type extensions
- Complex Ash types (UUID, CiString, etc.)

### Supporting Modules

#### `AshAgent.Sigils`
Provides `~p` sigil for compile-time Liquid template parsing.

**Purpose:** Catch template syntax errors at compile time rather than runtime.

#### `AshAgent.Transformers.ValidateAgent`
Spark transformer that validates agent configuration completeness.

**Checks performed:**
- Client is configured
- Output type is defined
- Prompt template exists
- Input arguments are valid

#### `AshAgent.Transformers.AddAgentActions`
Spark transformer that generates `:call` and `:stream` actions.

**Generated actions:**
- Map input arguments to action arguments
- Wire up to `AshAgent.Runtime.call/2` and `AshAgent.Runtime.stream/2`
- Integrate with Ash action system (authorization, policies, etc.)

## Data Flow

### Standard Agent Call

```
User Code
  ↓
MyAgent.call(message: "Hello")
  ↓
Ash Action System (generated :call action)
  ↓
AshAgent.Runtime.call(MyAgent, %{message: "Hello"})
  ↓
1. get_agent_config - Extract DSL config via Spark
  ↓
2. render_prompt - Process template with Solid
  ↓
3. build_schema - Convert TypedStruct via SchemaConverter
  ↓
4. generate_object - Call ReqLLM.generate_object
  ↓
5. build_result - Parse JSON to TypedStruct
  ↓
{:ok, %MyAgent.Reply{content: "Hello! How can I help?"}}
  ↓
User Code
```

### Streaming Call

Same flow as standard call, but step 4 uses `ReqLLM.stream_object` and returns a Stream that yields the final parsed object when JSON is complete.

## Extension Points & Limitations

### Current Extension Points

1. **Custom TypedStructs** - Users define their own output structures
2. **Prompt Templates** - Liquid syntax allows flexible prompting
3. **Client Options** - Pass-through to ReqLLM for model parameters
4. **Ash Actions** - Generated actions integrate with policies, preparations, etc.

### Current Limitations

1. **No middleware/hooks** - Can't intercept or modify execution
2. **Monolithic runtime** - Hard to swap components
3. **Limited type support** - No unions, discriminated unions, nested arrays
4. **No retry logic** - Fails immediately on errors
5. **No telemetry** - No observability into execution
6. **No streaming tokens** - Streams only yield final object
7. **Single LLM call** - No multi-step workflows or tool use
8. **No memory** - Stateless, no conversation history

## Dependencies

### Direct Dependencies

- **Ash** (~> 3.4) - Framework foundation
- **Spark** (~> 2.2) - DSL engine
- **req_llm** (~> 0.1.14) - Default LLM provider
- **solid** (~> 0.15.2) - Liquid template engine

### Optional Integrations

- **ash_baml** (~> 0.1, GitHub) - Alternate provider that reuses BAML functions

### Dependency Purposes

- **Spark** - Provides DSL infrastructure and validation
- **req_llm** - Default provider implementation for direct LLM calls
- **solid** - Liquid template rendering for prompts
- **Ash.TypedStruct** (via ash_baml or user modules) - Type-safe struct definitions
- **Ash** - Action system, authorization, domain modeling

### Provider Registry

Providers are resolved through `AshAgent.ProviderRegistry`, which loads built-in adapters
(`:req_llm`, `:mock`, `:baml`) and merges any user-defined providers configured via

```elixir
config :ash_agent,
  providers: [
    custom: MyApp.CustomProvider
  ]
```

Each provider implements `AshAgent.Provider` and receives the execution context so it can
render prompts (ReqLLM) or operate on structured inputs (ash_baml).

#### Capabilities

Providers declare capabilities (e.g., `:tool_calling`, `:streaming`) via their `introspect/0`
implementation. Compile-time validation ensures resource definitions only opt into features
the selected provider actually supports (for example, defining `tools` requires
`:tool_calling`). Promptless providers (e.g., `:baml`) advertise `:prompt_optional`, letting
agents skip the prompt DSL entirely. Custom providers should return a `%{features: [...]}`
map so the DSL can validate usage.

#### Telemetry

`AshAgent.Telemetry` emits spans for `[:ash_agent, :call]` and `[:ash_agent, :stream]`
around every provider interaction. Metadata includes the agent module, provider, client,
status, and—when exposed by the provider—token usage. Consumers can attach telemetry
handlers to integrate with metrics/observability stacks.

## Design Patterns

### Declarative Configuration
Uses Spark DSL to move configuration from code to declaration. Users describe *what* they want, transformers generate *how* to do it.

### Type Safety
TypedStruct output types ensure compile-time guarantees about response structure. SchemaConverter bridges TypedStruct and LLM schemas.

### Escape Hatches
Following ash_baml pattern: simple declarative API for 80% case, direct `AshAgent.Runtime` access for advanced needs.

### Integration Over Invention
Leverages existing Ash patterns (actions, policies, domains) rather than creating parallel systems.

## Future Evolution Points

Based on Phase 0 refactoring needs:

1. **Runtime Modularity**
   - Extract PromptRenderer
   - Extract LLMClient
   - Extract ResponseParser
   - Add Hook system

2. **Enhanced SchemaConverter**
   - Union type support
   - Discriminated unions
   - Nested arrays
   - Extension protocol

3. **Observability**
   - Telemetry events
   - Structured errors
   - Debug logging

4. **Resilience**
   - Retry logic
   - Fallback strategies
   - Error recovery

5. **Advanced Features** (post-Phase 0)
   - Tool/function calling
   - Multi-step workflows
   - Memory/state management
   - Multi-agent orchestration

## Comparison to Similar Frameworks

### vs LangChain (Python)
- **AshAgent**: Declarative, compile-time validation, BEAM concurrency
- **LangChain**: Imperative, runtime configuration, extensive integrations

### vs CrewAI (Python)
- **AshAgent**: Single agent focus (for now), Ash integration
- **CrewAI**: Multi-agent orchestration, role-based design

### vs LangGraph (Python)
- **AshAgent**: Action-based, simpler mental model
- **LangGraph**: Graph-based workflows, explicit state management

**AshAgent differentiators:**
- BEAM/OTP fault tolerance and concurrency
- Compile-time DSL validation
- Native Ash ecosystem integration
- Type-safe inputs/outputs
- Declarative-first with escape hatches
