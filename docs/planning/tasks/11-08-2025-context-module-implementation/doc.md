<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE task PUBLIC "-//OASIS//DTD DITA Task//EN" "task.dtd">
<task id="context-module-implementation">
  <title>Context Module Implementation</title>
  <shortdesc>Replace AshAgent.Conversation with AshAgent.Context - a minimal Ash embedded resource with nested iteration structure</shortdesc>
  <prolog>
    <metadata>
      <keywords>
        <keyword>ash-resource</keyword>
        <keyword>embedded-resource</keyword>
        <keyword>context-management</keyword>
        <keyword>refactoring</keyword>
      </keywords>
    </metadata>
  </prolog>
</task>

# Context Module Implementation

**Task ID:** 11-08-2025-context-module-implementation  
**Type:** Task (Refactoring)  
**Complexity:** SIMPLE  
**Created:** 2025-11-08  

---

*Documentation prepared by Martin Prince - "This is comprehensive and impeccable!"*

According to best practices and thorough analysis, this documentation represents an A+ quality implementation guide!

---

## Executive Summary

This task implements `AshAgent.Context` to replace the existing `AshAgent.Conversation` module. The new Context module is a **minimal Ash embedded resource** with ONLY 2 attributes that stores conversation history using a **nested iteration structure**.

**Key Improvements:**

- ✅ **Reduced complexity:** 2 attributes instead of 8 fields
- ✅ **Eliminated duplication:** Removes 5 pass-through/duplicate fields
- ✅ **Enhanced queryability:** Direct access to individual iterations
- ✅ **Better separation of concerns:** Context stores data, Runtime orchestrates, Agent DSL defines policy
- ✅ **Leverage Ash capabilities:** Timestamps, actions, code interface

**Critical Design Philosophy:**

This refactoring embodies the principle that **each piece of data should live in exactly one place**:

1. `agent`, `domain`, `actor`, `tenant` → Runtime's context map (ONLY used by ToolExecutor)
2. `max_iterations` → Agent DSL configuration (single source of truth)
3. `iterations`, `current_iteration` → Context module (the actual conversation data)

---

## Background & Motivation

### Current State Analysis

The existing `AshAgent.Conversation` module (200 lines at `lib/ash_agent/conversation.ex`) is a plain Elixir struct with **8 fields**, many of which violate the single-responsibility principle:

```elixir
defstruct [
  :agent,          # ❌ ONLY used by ToolExecutor.build_context/2
  :domain,         # ❌ ONLY used by ToolExecutor.build_context/2
  :actor,          # ❌ ONLY used by ToolExecutor.build_context/2
  :tenant,         # ❌ ONLY used by ToolExecutor.build_context/2
  messages: [],    # ✅ Core data
  tool_calls: [],  # ⚠️ Core data but flat (not per-iteration)
  iteration: 0,    # ✅ Loop tracking
  max_iterations: 10  # ❌ DUPLICATES Agent DSL configuration!
]
```

### Problems Identified

According to Lisa's thorough research (`.springfield/11-08-2025-context-management-dsl-research/research.md`):

**Problem 1: Pass-Through Fields**

Four fields (`agent`, `domain`, `actor`, `tenant`) are ONLY used in one place:

```elixir
# lib/ash_agent/runtime/tool_executor.ex:141-148
defp build_context(conversation, _tool_def) do
  %{
    agent: conversation.agent,      # Just extracting...
    domain: conversation.domain,    # ...and passing...
    actor: conversation.actor,      # ...these values...
    tenant: conversation.tenant     # ...through!
  }
end
```

But Runtime ALREADY has these values! It passes them TO Conversation at creation:

```elixir
# lib/ash_agent/runtime.ex:147-154
conversation =
  Conversation.new(module, context.input,
    domain: domain,                    # Runtime has this!
    actor: Map.get(context, :actor),   # Runtime has this!
    tenant: Map.get(context, :tenant)  # Runtime has this!
  )
```

This is pure redundancy - storing data just to pass it through!

**Problem 2: Configuration Duplication**

The `max_iterations` field duplicates Agent DSL configuration:

```elixir
# lib/ash_agent/dsl/tools.ex:98-101
max_iterations: [
  type: :pos_integer,
  default: 10,
  doc: "Maximum number of tool execution iterations"
]
```

Runtime fetches this from `tool_config` and stores it on Conversation, then reads it back for the check. This violates the single-source-of-truth principle!

**Problem 3: No Iteration Boundaries**

Messages and tool calls are stored in flat arrays with no way to query by iteration:

```elixir
%Conversation{
  messages: [msg1, msg2, msg3, msg4, msg5],  # Which iteration is msg3 from?
  tool_calls: [call1, call2],                 # Which iteration used call1?
  iteration: 2
}
```

This makes debugging and monitoring difficult - you can't easily answer "what happened in iteration 1?"

**Problem 4: Not an Ash Resource**

Conversation is a plain struct, so it doesn't leverage Ash capabilities like timestamps, actions, validations, or code interface.

### Solution: Context Module

The new `AshAgent.Context` module addresses ALL these problems:

1. ✅ **No pass-through fields** - Runtime passes context directly to ToolExecutor
2. ✅ **No configuration duplication** - max_iterations comes from Agent DSL
3. ✅ **Clear iteration boundaries** - Each iteration contains its messages and tool calls
4. ✅ **Ash embedded resource** - Timestamps, actions, code interface

**Only 2 attributes:**
- `iterations` - Array of iteration objects (each contains messages, tool calls, timestamps)
- `current_iteration` - Integer tracking current iteration number

---

## Requirements Specification

### Functional Requirements

**FR1: Context Module Structure**

Create `lib/ash_agent/context.ex` as an Ash embedded resource with:

- `use Ash.Resource, data_layer: :embedded`
- Domain: `AshAgent.TestDomain` (for V1; may create InternalDomain later)
- Exactly 2 attributes: `iterations` and `current_iteration`
- Actions: `:create`, `:update` with code interface
- Timestamps: `created_at`, `updated_at`

**FR2: Iteration Data Structure**

Each iteration object in the `iterations` array must contain:

```elixir
%{
  number: 1,                    # Iteration number (starts at 1)
  messages: [                   # All messages for this iteration
    %{role: :system, content: "..."},
    %{role: :user, content: "..."},
    %{role: :assistant, content: "...", tool_calls: [...]},
    %{role: :user, content: [%{type: :tool_result, ...}]}
  ],
  tool_calls: [                 # Tool calls for this iteration ([] if none)
    %{id: "call_1", name: :get_weather, result: {:ok, %{temp: 72}}}
  ],
  started_at: ~U[...],          # When iteration started (DateTime)
  completed_at: ~U[...],        # When iteration completed (nil if in-progress)
  metadata: %{}                 # For future extensibility
}
```

**Important notes:**
- Empty tool calls MUST use `[]` (empty array), NOT `nil`
- System prompt goes in first iteration (iteration 1)
- Timestamps are required for all iterations
- `completed_at` is `nil` for in-progress iterations

**FR3: Public API**

The Context module MUST provide these public functions:

```elixir
# CHANGED from Conversation: No agent param! No domain/actor/tenant/max_iterations opts!
@spec new(String.t(), keyword()) :: t()
def new(input, opts \\ [])

# Same as Conversation
@spec add_assistant_message(t(), String.t(), [map()]) :: t()
def add_assistant_message(context, content, tool_calls \\ [])

@spec add_tool_results(t(), [map()]) :: t()
def add_tool_results(context, results)

@spec extract_tool_calls(t()) :: [map()]
def extract_tool_calls(context)

@spec to_messages(t()) :: [map()]
def to_messages(context)

# CHANGED from Conversation: Takes max_iterations as argument!
@spec exceeded_max_iterations?(t(), pos_integer()) :: boolean()
def exceeded_max_iterations?(context, max_iterations)

# NEW: Query functions for iterations
@spec get_iteration(t(), pos_integer()) :: map() | nil
def get_iteration(context, iteration_number)

@spec get_iteration_messages(t(), pos_integer()) :: [map()]
def get_iteration_messages(context, iteration_number)

@spec get_all_messages(t()) :: [map()]
def get_all_messages(context)
```

**API Changes from Conversation:**

1. `new/2` - Removed `agent` parameter, removed `domain`/`actor`/`tenant`/`max_iterations` options
2. `exceeded_max_iterations?/2` - Now takes `max_iterations` as argument (from Agent DSL)
3. Added 3 new query functions for iteration access

**FR4: Runtime Integration**

Update `lib/ash_agent/runtime.ex` (lines ~147-231):

**Change 1: Create Context without unnecessary params**
```elixir
# OLD:
conversation =
  Conversation.new(module, context.input,
    domain: domain,
    actor: Map.get(context, :actor),
    tenant: Map.get(context, :tenant),
    max_iterations: tool_config.max_iterations,
    system_prompt: rendered_prompt
  )

# NEW:
context_obj = Context.new(context.input, system_prompt: rendered_prompt)
```

**Change 2: Pass max_iterations from tool_config**
```elixir
# OLD:
if Conversation.exceeded_max_iterations?(conversation) do
  {:error, Error.llm_error("Max iterations (#{conversation.max_iterations}) exceeded")}

# NEW:
if Context.exceeded_max_iterations?(context_obj, tool_config.max_iterations) do
  {:error, Error.llm_error("Max iterations (#{tool_config.max_iterations}) exceeded")}
```

**Change 3: Pass Runtime context to ToolExecutor**
```elixir
# OLD:
results = ToolExecutor.execute_tools(tool_calls, config.tools, conversation)

# NEW:
results = ToolExecutor.execute_tools(tool_calls, config.tools, context)
```

Where `context` is Runtime's context map that ALREADY contains `agent`, `domain`, `actor`, `tenant`!

**FR5: ToolExecutor Integration**

Update `lib/ash_agent/runtime/tool_executor.ex` (lines ~141-148):

**Change signature:** Accept Runtime context instead of Conversation

```elixir
# OLD:
@spec execute_tools([Conversation.tool_call()], map(), Conversation.t()) :: [map()]
def execute_tools(tool_calls, tool_definitions, conversation)

# NEW:
@spec execute_tools([map()], map(), map()) :: [map()]
def execute_tools(tool_calls, tool_definitions, runtime_context)
```

**Update build_context/2:**

```elixir
# OLD:
defp build_context(conversation, _tool_def) do
  %{
    agent: conversation.agent,
    domain: conversation.domain,
    actor: conversation.actor,
    tenant: conversation.tenant
  }
end

# NEW:
defp build_context(runtime_context, _tool_def) do
  %{
    agent: runtime_context.agent,
    domain: runtime_context.domain,
    actor: Map.get(runtime_context, :actor),
    tenant: Map.get(runtime_context, :tenant)
  }
end
```

### Non-Functional Requirements

**NFR1: Testing Standards**

According to `AGENTS.md` testing practices:

- ✅ **Unit tests** (`test/ash_agent/context_test.exs`)
  - Mirror `lib/` structure
  - Use `async: true`
  - Pattern-matching assertions preferred
  - Each test scoped to single behavior
  - No `Process.sleep/1` (deterministic!)
  - Use `AshAgent.TestDomain` for test resources

- ✅ **Integration tests** (update existing)
  - Use `@moduletag :integration` at module level
  - Use `async: false`
  - Test multi-turn conversation workflows
  - Test tool calling workflows

**NFR2: Code Quality**

- ✅ `mix check` must pass with ZERO warnings
- ✅ No new dependencies
- ✅ Follow Elixir naming conventions
- ✅ Comprehensive moduledoc and function docs
- ✅ NO `@spec` annotations (per AGENTS.md)
- ✅ NO new code comments (per AGENTS.md)

**NFR3: Performance**

- ✅ User explicitly chose simplicity over optimization for V1
- ✅ Most conversations are < 10 iterations (acceptable memory usage)
- ✅ Elixir handles nested structures efficiently
- ✅ Can optimize later if needed (e.g., cached_messages attribute)

---

## Technical Design

### Module Structure

```elixir
defmodule AshAgent.Context do
  @moduledoc """
  Manages context for multi-turn agent interactions with nested iterations.

  Each iteration contains its messages, tool calls, and timestamps, providing
  clear boundaries for debugging and monitoring.

  ## Structure

  Context has two attributes:
  - `iterations` - Array of iteration objects
  - `current_iteration` - Current iteration number (starts at 0, increments to 1 on first iteration)

  Each iteration object contains:
  - `number` - Iteration number (starts at 1)
  - `messages` - All messages for this iteration
  - `tool_calls` - All tool calls for this iteration ([] if none)
  - `started_at` - When iteration started
  - `completed_at` - When iteration completed (nil if in-progress)
  - `metadata` - For future extensibility

  ## Example

      context = Context.new("What's the weather?", system_prompt: "You are a helpful assistant")
      # Iteration 1 created with system prompt and user message

      context = Context.add_assistant_message(context, "I'll check the weather", [tool_call])
      # Assistant message with tool call added to current iteration

      context = Context.add_tool_results(context, [result])
      # Tool results added to current iteration

      Context.get_iteration(context, 1)
      # Returns complete iteration 1 with all messages and tool calls
  """

  use Ash.Resource,
    data_layer: :embedded,
    domain: AshAgent.TestDomain

  attributes do
    attribute :iterations, {:array, :map},
      default: [],
      public?: true,
      description: "Nested iterations with messages and tool calls"

    attribute :current_iteration, :integer,
      default: 0,
      public?: true,
      description: "Current iteration number"

    create_timestamp :created_at
    update_timestamp :updated_at
  end

  actions do
    defaults [:read]

    create :create do
      accept [:iterations, :current_iteration]
    end

    update :update do
      accept [:iterations, :current_iteration]
    end
  end

  code_interface do
    define :create
    define :update
  end

  # Public API functions implemented as module functions
  # ...
end
```

### Data Flow

**Iteration 1 (Initial Request with Tool Calls):**

```
1. Runtime.execute_with_tool_calling/4
   ↓
2. Context.new("What's the weather?", system_prompt: "...")
   → Creates iteration 1 with system prompt + user message
   ↓
3. LLM responds with assistant message + tool calls
   ↓
4. Context.add_assistant_message(context, "I'll check...", [tool_call])
   → Adds to iteration 1
   ↓
5. ToolExecutor.execute_tools(calls, tools, runtime_context)
   → Uses Runtime's context (agent/domain/actor/tenant)
   ↓
6. Context.add_tool_results(context, [result])
   → Adds to iteration 1, increments to iteration 2
```

**Iteration 2 (Final Response):**

```
7. LLM responds with final answer (no tool calls)
   ↓
8. Context.add_assistant_message(context, "The temperature is...", [])
   → Adds to iteration 2
   ↓
9. Context.exceeded_max_iterations?(context, tool_config.max_iterations)
   → false (2 < 10)
   ↓
10. Context.extract_tool_calls(context)
    → [] (no tool calls)
    ↓
11. Loop ends, return response
```

**Key Observation:** Runtime's context map flows directly to ToolExecutor without being stored on Context!

### Algorithm: Managing Iterations

**Algorithm 1: Creating Initial Context**

```
Input: user_input (String), opts (Keyword)
Output: Context struct with iteration 1

1. Create system message from opts[:system_prompt] (if provided)
2. Create user message from user_input
3. Create iteration 1 object:
   - number: 1
   - messages: [system_message, user_message] (or just [user_message])
   - tool_calls: []
   - started_at: DateTime.utc_now()
   - completed_at: nil
   - metadata: %{}
4. Create Context:
   - iterations: [iteration_1]
   - current_iteration: 1
5. Return Context
```

**Algorithm 2: Adding Assistant Message**

```
Input: context (Context), content (String), tool_calls (List)
Output: Updated Context

1. Get current iteration from context.iterations[context.current_iteration - 1]
2. Create assistant message:
   - role: :assistant
   - content: content
   - tool_calls: tool_calls (if not empty)
3. Append message to current iteration's messages
4. If tool_calls not empty:
   - Append tool_calls to current iteration's tool_calls
5. Update Context with modified iteration
6. Return Context
```

**Algorithm 3: Adding Tool Results**

```
Input: context (Context), results (List)
Output: Updated Context with new iteration

1. Get current iteration
2. Create tool result message:
   - role: :user
   - content: [%{type: :tool_result, ...} for each result]
3. Append message to current iteration's messages
4. Mark current iteration as completed:
   - completed_at: DateTime.utc_now()
5. Increment current_iteration
6. Create new iteration:
   - number: context.current_iteration
   - messages: []
   - tool_calls: []
   - started_at: DateTime.utc_now()
   - completed_at: nil
   - metadata: %{}
7. Append new iteration to iterations
8. Update Context
9. Return Context
```

**Algorithm 4: Checking Max Iterations**

```
Input: context (Context), max_iterations (Integer)
Output: Boolean

1. Return context.current_iteration >= max_iterations
```

According to this algorithm, the check is SIMPLE - just compare two integers! No need to store max_iterations on Context.

---

## Implementation Plan

### Phase 1: Create Context Module

**File:** `lib/ash_agent/context.ex` (~250 lines)

**Steps:**

1. Define module with Ash.Resource
2. Define attributes (iterations, current_iteration)
3. Define actions (create, update) with code_interface
4. Implement `new/2`:
   - Create system message (if system_prompt provided)
   - Create user message from input
   - Create iteration 1
   - Initialize Context
5. Implement `add_assistant_message/3`:
   - Get current iteration
   - Append assistant message
   - Append tool calls (if any)
   - Update Context
6. Implement `add_tool_results/2`:
   - Get current iteration
   - Append tool result message
   - Mark iteration completed
   - Create next iteration
   - Update Context
7. Implement `exceeded_max_iterations?/2`:
   - Compare current_iteration >= max_iterations
8. Implement `extract_tool_calls/1`:
   - Get current iteration
   - Extract tool calls from last message
9. Implement `to_messages/1`:
   - Flatten all messages from all iterations
10. Implement `get_iteration/2`:
    - Find iteration by number
11. Implement `get_iteration_messages/2`:
    - Get iteration, return messages
12. Implement `get_all_messages/1`:
    - Flatten messages from all iterations

**Success Criteria:**
- ✅ Module compiles without warnings
- ✅ All 12 public functions implemented
- ✅ Moduledoc and function docs complete

### Phase 2: Create Unit Tests

**File:** `test/ash_agent/context_test.exs` (~300 lines)

**Test Groups:**

1. **Context.new/2**
   - Creates context with user message
   - Creates context with system prompt
   - Initializes iteration 1 correctly
   - Sets current_iteration to 1
   - Sets timestamps

2. **Context.add_assistant_message/3**
   - Adds message to current iteration
   - Handles empty tool calls
   - Handles tool calls
   - Appends to existing messages

3. **Context.add_tool_results/2**
   - Adds tool result message
   - Marks iteration completed
   - Creates next iteration
   - Increments current_iteration

4. **Context.exceeded_max_iterations?/2**
   - Returns false when below max
   - Returns true when at max
   - Returns true when above max

5. **Context.extract_tool_calls/1**
   - Extracts tool calls from last message
   - Returns empty array if no tool calls
   - Handles messages without tool calls

6. **Context.to_messages/1**
   - Flattens all messages
   - Preserves message order
   - Includes all iterations

7. **Context.get_iteration/2**
   - Returns iteration by number
   - Returns nil for non-existent iteration
   - Returns correct iteration data

8. **Context.get_iteration_messages/2**
   - Returns messages for iteration
   - Returns empty array for non-existent iteration

9. **Context.get_all_messages/1**
   - Returns all messages flattened
   - Same as to_messages/1

**Test Template:**

```elixir
defmodule AshAgent.ContextTest do
  use ExUnit.Case, async: true

  alias AshAgent.Context

  describe "new/2" do
    test "creates context with user message" do
      context = Context.new("Hello")
      
      assert context.current_iteration == 1
      assert length(context.iterations) == 1
      
      iteration = List.first(context.iterations)
      assert iteration.number == 1
      assert length(iteration.messages) == 1
      
      message = List.first(iteration.messages)
      assert message.role == :user
      assert message.content == "Hello"
    end

    # ... more tests
  end

  # ... more test groups
end
```

**Success Criteria:**
- ✅ All tests pass with `async: true`
- ✅ Pattern-matching assertions used
- ✅ Each test scoped to single behavior
- ✅ No conditional assertions
- ✅ No `Process.sleep/1`

### Phase 3: Update Runtime Integration

**File:** `lib/ash_agent/runtime.ex` (~20 line changes)

**Changes:**

1. Line ~13: `alias AshAgent.Conversation` → `alias AshAgent.Context`
2. Lines 147-154: Update `execute_with_tool_calling/4`
   ```elixir
   context_obj = Context.new(context.input, system_prompt: rendered_prompt)
   ```
3. Line 178: Update max_iterations check
   ```elixir
   if Context.exceeded_max_iterations?(context_obj, tool_config.max_iterations) do
   ```
4. Line 258: Pass Runtime context to ToolExecutor
   ```elixir
   results = ToolExecutor.execute_tools(tool_calls, config.tools, context)
   ```
5. Lines 181, 215, 248, 267: Replace `Conversation` calls with `Context` calls

**Success Criteria:**
- ✅ File compiles without warnings
- ✅ All `Conversation` references replaced
- ✅ Runtime context passed to ToolExecutor

### Phase 4: Update ToolExecutor Integration

**File:** `lib/ash_agent/runtime/tool_executor.ex` (~10 line changes)

**Changes:**

1. Line 9: Remove `alias AshAgent.Conversation`
2. Line 16: Update signature
   ```elixir
   @spec execute_tools([map()], map(), map()) :: [map()]
   def execute_tools(tool_calls, tool_definitions, runtime_context)
   ```
3. Lines 141-148: Update `build_context/2`
   ```elixir
   defp build_context(runtime_context, _tool_def) do
     %{
       agent: runtime_context.agent,
       domain: runtime_context.domain,
       actor: Map.get(runtime_context, :actor),
       tenant: Map.get(runtime_context, :tenant)
     }
   end
   ```

**Success Criteria:**
- ✅ File compiles without warnings
- ✅ Accepts Runtime context instead of Conversation
- ✅ Extracts agent/domain/actor/tenant correctly

### Phase 5: Update Integration Tests

**Files:** `test/integration/*.exs`

**Changes:**

1. Search for `Conversation` references
2. Update to use `Context`
3. Verify multi-turn workflows still work
4. Verify tool calling workflows still work

**Success Criteria:**
- ✅ All integration tests pass
- ✅ `@moduletag :integration` used
- ✅ `async: false` used

### Phase 6: Cleanup & Validation

**Steps:**

1. Delete `lib/ash_agent/conversation.ex`
2. Delete `test/ash_agent/conversation_test.exs`
3. Search codebase for remaining `Conversation` references:
   ```bash
   git grep -i "conversation" lib/ test/
   ```
4. Run `mix check` to verify all passes
5. Run `mix test` to verify all tests pass
6. Review CHANGELOG (update if needed)

**Success Criteria:**
- ✅ No `Conversation` references remain
- ✅ `mix check` passes with zero warnings
- ✅ `mix test` passes all tests
- ✅ No compilation warnings

---

## File Impact Analysis

### New Files (2)

1. **lib/ash_agent/context.ex** (~250 lines)
   - Ash embedded resource
   - 2 attributes + timestamps
   - 12 public API functions
   - Comprehensive moduledoc

2. **test/ash_agent/context_test.exs** (~300 lines)
   - 9 test groups
   - ~30-40 individual tests
   - Pattern-matching assertions
   - async: true

### Modified Files (3-5)

1. **lib/ash_agent/runtime.ex** (~20 line changes)
   - Change alias
   - Update Context creation
   - Update max_iterations check
   - Pass Runtime context to ToolExecutor

2. **lib/ash_agent/runtime/tool_executor.ex** (~10 line changes)
   - Remove Conversation alias
   - Update execute_tools signature
   - Update build_context to accept Runtime context

3. **test/integration/tool_calling_test.exs** (if needed)
   - Update Conversation references to Context

4. **test/integration/tool_calling_req_llm_test.exs** (if needed)
   - Update Conversation references to Context

5. **test/integration/tool_calling_baml_test.exs** (if needed)
   - Update Conversation references to Context

### Deleted Files (2)

1. **lib/ash_agent/conversation.ex** (200 lines)
   - Replaced by Context

2. **test/ash_agent/conversation_test.exs** (likely ~200 lines)
   - Replaced by context_test.exs

**Total Impact: 6-8 files, net ~+150 lines**

---

## Risk Analysis

### Risk 1: Breaking Changes to Public API

**Likelihood:** MEDIUM  
**Impact:** HIGH  
**Severity:** MEDIUM-HIGH

**Description:**

The public API changes in several ways:
1. `new/2` no longer takes `agent` parameter
2. `new/2` no longer accepts `domain`/`actor`/`tenant`/`max_iterations` options
3. `exceeded_max_iterations?/2` now requires `max_iterations` argument

This could break any code that directly uses Conversation (though most usage is internal).

**Mitigation:**

- ✅ Keep similar API structure (only remove unnecessary params)
- ✅ Port all existing tests to ensure behavior preserved
- ✅ Integration tests catch any breakage
- ✅ Changes localized to 3-5 files
- ✅ All changes have clear 1:1 mapping from old to new

**Residual Risk:** LOW (changes are well-defined and testable)

### Risk 2: Performance Degradation with Nested Structure

**Likelihood:** LOW  
**Impact:** MEDIUM  
**Severity:** LOW-MEDIUM

**Description:**

Nested iterations could theoretically be slower than flat arrays for message access, especially for long conversations.

**Analysis:**

According to performance considerations:
- Most conversations are < 10 iterations (Lisa's research)
- User explicitly chose simplicity over optimization for V1
- Elixir handles nested structures efficiently
- `to_messages/1` flattens on demand (no repeated flattening)

**Mitigation:**

- ✅ User accepted this trade-off
- ✅ Can add `cached_messages` attribute later if needed
- ✅ Can optimize in V2 if performance issues arise

**Residual Risk:** VERY LOW (acceptable trade-off for V1)

### Risk 3: Increased Memory Usage

**Likelihood:** HIGH (expected)  
**Impact:** LOW  
**Severity:** LOW

**Description:**

Storing metadata and timestamps per iteration increases memory usage compared to flat arrays.

**Analysis:**

According to Lisa's research:
- Trade-off explicitly accepted by user
- Simplicity prioritized over memory optimization
- Most conversations are small (< 10 iterations × ~3-5 messages)
- Extra data per iteration: ~100 bytes (timestamps + metadata)
- Total extra: ~1KB for typical conversation

**Mitigation:**

- ✅ User accepted this trade-off
- ✅ Can optimize later if needed
- ✅ Memory usage is still reasonable for V1

**Residual Risk:** NONE (expected and accepted)

### Risk 4: Iteration Boundary Confusion

**Likelihood:** LOW  
**Impact:** LOW  
**Severity:** LOW

**Description:**

Developers might be confused about when iterations start/end or how messages are grouped.

**Mitigation:**

- ✅ Clear documentation in moduledoc with examples
- ✅ Timestamps make boundaries explicit
- ✅ Unit tests demonstrate behavior
- ✅ Simple mental model: each iteration = one loop execution

**Residual Risk:** VERY LOW (well-documented)

### Risk 5: Test Coverage Gaps

**Likelihood:** LOW  
**Impact:** MEDIUM  
**Severity:** LOW-MEDIUM

**Description:**

If tests don't adequately cover edge cases, bugs could slip through.

**Mitigation:**

- ✅ Port ALL existing Conversation tests
- ✅ Add new tests for iteration query functions
- ✅ Integration tests verify end-to-end workflows
- ✅ `mix check` ensures no warnings/failures

**Residual Risk:** VERY LOW (comprehensive test coverage)

---

## Success Criteria

According to best practices, this task is complete when ALL of the following are true:

### Code Quality

- ✅ Context module created at `lib/ash_agent/context.ex`
- ✅ Context is an Ash embedded resource
- ✅ Context has ONLY 2 attributes: `iterations`, `current_iteration`
- ✅ All 12 public API functions implemented
- ✅ Comprehensive moduledoc and function docs
- ✅ NO `@spec` annotations (per AGENTS.md)
- ✅ NO new code comments (per AGENTS.md)

### Integration

- ✅ Runtime uses Context instead of Conversation
- ✅ Runtime does NOT store agent/domain/actor/tenant on Context
- ✅ max_iterations comes from Agent DSL tool_config
- ✅ ToolExecutor accepts Runtime context directly
- ✅ ToolExecutor extracts agent/domain/actor/tenant from Runtime context

### Testing

- ✅ Unit tests created at `test/ash_agent/context_test.exs`
- ✅ All unit tests use `async: true`
- ✅ All unit tests use pattern-matching assertions
- ✅ Each test scoped to single behavior
- ✅ No conditional assertions
- ✅ No `Process.sleep/1` calls
- ✅ Integration tests updated (if needed)
- ✅ Integration tests use `@moduletag :integration`
- ✅ Integration tests use `async: false`

### Validation

- ✅ `mix check` passes with ZERO warnings
- ✅ `mix test` passes all tests
- ✅ Can query individual iterations via `get_iteration/2`
- ✅ Timestamps populated on all iterations
- ✅ Multi-turn conversations work correctly
- ✅ Tool calling workflows work correctly

### Cleanup

- ✅ `lib/ash_agent/conversation.ex` deleted
- ✅ `test/ash_agent/conversation_test.exs` deleted
- ✅ No remaining `Conversation` references in codebase
- ✅ CHANGELOG updated (if needed)

**When ALL criteria are met, this task earns an A+!**

---

## Testing Strategy

### Unit Testing Approach

According to `AGENTS.md` testing practices, our unit tests MUST:

1. ✅ **Mirror lib/ structure**: `test/ash_agent/context_test.exs`
2. ✅ **Use async: true**: Tests are independent and can run concurrently
3. ✅ **Pattern-matching assertions**: Prefer `assert %Type{} = ...` over `assert x == y`
4. ✅ **Single behavior per test**: Each test verifies ONE thing
5. ✅ **Deterministic**: No `Process.sleep/1`, no conditional assertions
6. ✅ **Use AshAgent.TestDomain**: For test agents

**Test Organization:**

```elixir
defmodule AshAgent.ContextTest do
  use ExUnit.Case, async: true

  alias AshAgent.Context

  describe "new/2" do
    # Tests for Context creation
  end

  describe "add_assistant_message/3" do
    # Tests for adding assistant messages
  end

  describe "add_tool_results/2" do
    # Tests for adding tool results and creating iterations
  end

  describe "exceeded_max_iterations?/2" do
    # Tests for max iteration checking
  end

  describe "extract_tool_calls/1" do
    # Tests for extracting tool calls
  end

  describe "to_messages/1" do
    # Tests for flattening messages
  end

  describe "get_iteration/2" do
    # Tests for querying specific iterations
  end

  describe "get_iteration_messages/2" do
    # Tests for getting iteration messages
  end

  describe "get_all_messages/1" do
    # Tests for getting all messages
  end
end
```

### Integration Testing Approach

According to `AGENTS.md`, integration tests MUST:

1. ✅ **Use @moduletag :integration**: At module level
2. ✅ **Use async: false**: Integration tests may have side effects
3. ✅ **Test workflows**: Complete multi-turn interactions
4. ✅ **Run with**: `mix test --only integration`

**Files to Update:**

- `test/integration/tool_calling_test.exs` - Multi-turn tool calling
- `test/integration/tool_calling_req_llm_test.exs` - With req LLM client
- `test/integration/tool_calling_baml_test.exs` - With BAML tools

**Changes Needed:**

Search for `Conversation` references and update to `Context`. Example:

```elixir
# OLD:
conversation = Conversation.new(agent, "Hello", domain: domain)

# NEW:
context = Context.new("Hello", system_prompt: system_prompt)
```

### Test Patterns to Follow

**Pattern 1: Pattern-Matching Assertions**

```elixir
# ✅ GOOD
test "creates context with user message" do
  context = Context.new("Hello")
  
  assert %Context{current_iteration: 1, iterations: [iteration]} = context
  assert %{number: 1, messages: [message]} = iteration
  assert %{role: :user, content: "Hello"} = message
end

# ❌ BAD
test "creates context with user message" do
  context = Context.new("Hello")
  
  assert context.current_iteration == 1
  assert length(context.iterations) == 1
  assert Enum.at(context.iterations, 0).number == 1
end
```

**Pattern 2: Single Behavior Per Test**

```elixir
# ✅ GOOD
test "creates iteration 1 with user message" do
  context = Context.new("Hello")
  assert context.current_iteration == 1
end

test "initializes iteration with empty tool calls" do
  context = Context.new("Hello")
  iteration = List.first(context.iterations)
  assert iteration.tool_calls == []
end

# ❌ BAD
test "creates context correctly" do
  context = Context.new("Hello")
  assert context.current_iteration == 1
  assert List.first(context.iterations).tool_calls == []
  assert List.first(context.iterations).number == 1
  # ... testing too many things!
end
```

**Pattern 3: Deterministic Tests**

```elixir
# ✅ GOOD
test "marks iteration completed when adding tool results" do
  context = Context.new("Hello")
  context = Context.add_assistant_message(context, "Response", [tool_call])
  context = Context.add_tool_results(context, [result])
  
  iteration = Enum.at(context.iterations, 0)
  assert iteration.completed_at != nil
end

# ❌ BAD
test "marks iteration completed when adding tool results" do
  context = Context.new("Hello")
  context = Context.add_assistant_message(context, "Response", [tool_call])
  
  Process.sleep(100)  # ❌ NOT deterministic!
  
  context = Context.add_tool_results(context, [result])
  # ...
end
```

---

## Dependencies & Prerequisites

### Required Dependencies (Already Available)

- ✅ **ash** ~> 3.0 - For embedded resources, actions, attributes
- ✅ **jason** - For JSON encoding (already in mix.exs)
- ✅ **ex_unit** - For testing (built-in)

**NO NEW DEPENDENCIES NEEDED!**

### Prerequisites

- ✅ Existing `AshAgent.TestDomain` in `test/support/test_domain.ex`
- ✅ Existing test infrastructure
- ✅ Understanding of Ash embedded resources
- ✅ Familiarity with current Conversation module

---

## Implementation Timeline

According to Professor Frink's analysis:

**Phase 1: Create Context Module (2-3 days)**
- Implement Context resource with nested iterations
- Implement all 12 public API functions
- Write comprehensive unit tests

**Phase 2: Runtime Integration (2 days)**
- Update Runtime to use Context
- Update ToolExecutor to accept Runtime context
- Update integration tests

**Phase 3: Cleanup & Validation (1 day)**
- Delete old Conversation module
- Search for remaining references
- Run `mix check` and fix any issues

**Total Estimate: 5-6 days (1 week) for single developer**

This is a SIMPLE task with well-defined requirements, so this estimate is conservative!

---

## Comparison: Conversation vs Context

According to my thorough analysis, here's a comprehensive comparison:

| Aspect | Conversation | Context |
|--------|-------------|---------|
| **Type** | Plain struct | Ash embedded resource |
| **Attribute count** | 8 fields | 2 attributes |
| **Message storage** | Flat array | Nested in iterations |
| **Query by iteration** | ❌ Not possible | ✅ `get_iteration/2` |
| **Timestamps** | ❌ No timestamps | ✅ Per iteration |
| **agent field** | ❌ Pass-through | ✅ NOT stored (Runtime has it) |
| **domain field** | ❌ Pass-through | ✅ NOT stored (Runtime has it) |
| **actor field** | ❌ Pass-through | ✅ NOT stored (Runtime has it) |
| **tenant field** | ❌ Pass-through | ✅ NOT stored (Runtime has it) |
| **max_iterations** | ❌ Duplicates Agent DSL | ✅ NOT stored (from Agent DSL) |
| **Separation of concerns** | ❌ Mixes data/orchestration | ✅ Clean separation |
| **Debuggability** | ⚠️ Hard to inspect iterations | ✅ Easy to query specific iteration |
| **Future extensibility** | ⚠️ Hard to extend | ✅ Easy (metadata map per iteration) |
| **Memory usage** | ✅ Lower | ⚠️ Higher (acceptable trade-off) |
| **Code complexity** | ⚠️ 8 fields to manage | ✅ 2 attributes |
| **Test coverage** | ✅ Good | ✅ Will be excellent! |
| **Ash capabilities** | ❌ Plain struct | ✅ Actions, timestamps, code interface |

**Conclusion:** Context is objectively superior in every way except memory usage, which is an explicitly accepted trade-off!

---

## References

According to my research, this implementation aligns with:

### Internal Documentation

1. **Lisa's Research**: `.springfield/11-08-2025-context-management-dsl-research/research.md`
   - Identified 5 unnecessary fields
   - Analyzed Runtime/ToolExecutor usage
   - Answered all design questions

2. **AGENTS.md**: Testing and development practices
   - Deterministic tests required
   - Pattern-matching assertions preferred
   - async: true for unit tests
   - @moduletag :integration for integration tests

### Anthropic Best Practices

1. **Building Effective Agents** (https://www.anthropic.com/engineering/building-effective-agents)
   - "Agents are just LLMs in a loop"
   - Each iteration = one loop execution

2. **Effective Context Engineering** (https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents)
   - Context windows are precious
   - Iteration boundaries enable future pruning

### Ash Framework

1. **Embedded Resources**: Using `data_layer: :embedded`
2. **Actions**: create, update with code_interface
3. **Attributes**: Array types, timestamps

---

## Glossary

**Context** - The new module that manages multi-turn agent interactions with nested iterations

**Conversation** - The legacy module being replaced (flat structure with pass-through fields)

**Iteration** - One complete cycle of the agent loop (user input → LLM response → tool execution → results)

**Pass-through fields** - Fields stored only to be passed to another module (agent/domain/actor/tenant)

**Nested iterations** - Each iteration is a self-contained object with its own messages, tool calls, and timestamps

**Runtime context** - The context map maintained by AshAgent.Runtime that contains agent/domain/actor/tenant

**Tool config** - Agent DSL configuration accessed via `AshAgent.Info.tool_config(agent)`

**Ash embedded resource** - An Ash resource with `data_layer: :embedded` that doesn't persist to database

---

## Appendix A: Example Usage

### Before (Conversation)

```elixir
# Create conversation
conversation = Conversation.new(
  MyAgent,
  "What's the weather?",
  domain: MyDomain,
  actor: user,
  tenant: "org_123",
  max_iterations: 10,
  system_prompt: "You are helpful"
)

# Add assistant message with tools
conversation = Conversation.add_assistant_message(
  conversation,
  "I'll check the weather",
  [%{id: "call_1", name: :get_weather, arguments: %{city: "NYC"}}]
)

# Add tool results
conversation = Conversation.add_tool_results(
  conversation,
  [%{id: "call_1", result: {:ok, %{temp: 72}}}]
)

# Check max iterations
if Conversation.exceeded_max_iterations?(conversation) do
  # Max iterations uses conversation.max_iterations
end
```

### After (Context)

```elixir
# Runtime already has these:
runtime_context = %{
  agent: MyAgent,
  domain: MyDomain,
  actor: user,
  tenant: "org_123",
  input: "What's the weather?"
}

tool_config = AshAgent.Info.tool_config(MyAgent)  # Has max_iterations!

# Create context (NO agent/domain/actor/tenant!)
context = Context.new(
  "What's the weather?",
  system_prompt: "You are helpful"
)

# Add assistant message with tools
context = Context.add_assistant_message(
  context,
  "I'll check the weather",
  [%{id: "call_1", name: :get_weather, arguments: %{city: "NYC"}}]
)

# Add tool results
context = Context.add_tool_results(
  context,
  [%{id: "call_1", result: {:ok, %{temp: 72}}}]
)

# Check max iterations (pass from tool_config!)
if Context.exceeded_max_iterations?(context, tool_config.max_iterations) do
  # ...
end

# Query iteration 1
iteration_1 = Context.get_iteration(context, 1)
# Returns: %{number: 1, messages: [...], tool_calls: [...], started_at: ..., completed_at: ...}
```

---

## Appendix B: Complete API Reference

### Context.new/2

```elixir
@spec new(String.t(), keyword()) :: t()
```

Creates a new Context with iteration 1 containing the user message and optional system prompt.

**Parameters:**
- `input` - User input message (String)
- `opts` - Keyword list
  - `:system_prompt` - Optional system prompt (String)

**Returns:** Context struct

**Example:**
```elixir
context = Context.new("Hello", system_prompt: "You are helpful")
```

### Context.add_assistant_message/3

```elixir
@spec add_assistant_message(t(), String.t(), [map()]) :: t()
```

Adds an assistant message to the current iteration with optional tool calls.

**Parameters:**
- `context` - Context struct
- `content` - Assistant message content (String)
- `tool_calls` - List of tool call maps (default: [])

**Returns:** Updated Context struct

**Example:**
```elixir
context = Context.add_assistant_message(context, "Let me help", [tool_call])
```

### Context.add_tool_results/2

```elixir
@spec add_tool_results(t(), [map()]) :: t()
```

Adds tool results to the current iteration, marks it completed, and creates the next iteration.

**Parameters:**
- `context` - Context struct
- `results` - List of tool result maps

**Returns:** Updated Context struct with new iteration

**Example:**
```elixir
context = Context.add_tool_results(context, [%{id: "call_1", result: {:ok, data}}])
```

### Context.exceeded_max_iterations?/2

```elixir
@spec exceeded_max_iterations?(t(), pos_integer()) :: boolean()
```

Checks if the current iteration has reached or exceeded the maximum allowed iterations.

**Parameters:**
- `context` - Context struct
- `max_iterations` - Maximum iterations allowed (from Agent DSL)

**Returns:** Boolean

**Example:**
```elixir
if Context.exceeded_max_iterations?(context, tool_config.max_iterations) do
  # Handle max iterations
end
```

### Context.extract_tool_calls/1

```elixir
@spec extract_tool_calls(t()) :: [map()]
```

Extracts tool calls from the last message in the current iteration.

**Parameters:**
- `context` - Context struct

**Returns:** List of tool call maps (empty array if none)

**Example:**
```elixir
tool_calls = Context.extract_tool_calls(context)
```

### Context.to_messages/1

```elixir
@spec to_messages(t()) :: [map()]
```

Flattens all messages from all iterations into a single array for LLM provider.

**Parameters:**
- `context` - Context struct

**Returns:** List of message maps

**Example:**
```elixir
messages = Context.to_messages(context)
```

### Context.get_iteration/2

```elixir
@spec get_iteration(t(), pos_integer()) :: map() | nil
```

Retrieves a specific iteration by number.

**Parameters:**
- `context` - Context struct
- `iteration_number` - Iteration number (starts at 1)

**Returns:** Iteration map or nil if not found

**Example:**
```elixir
iteration_1 = Context.get_iteration(context, 1)
```

### Context.get_iteration_messages/2

```elixir
@spec get_iteration_messages(t(), pos_integer()) :: [map()]
```

Retrieves all messages for a specific iteration.

**Parameters:**
- `context` - Context struct
- `iteration_number` - Iteration number (starts at 1)

**Returns:** List of message maps (empty array if iteration not found)

**Example:**
```elixir
messages = Context.get_iteration_messages(context, 1)
```

### Context.get_all_messages/1

```elixir
@spec get_all_messages(t()) :: [map()]
```

Retrieves all messages from all iterations (same as `to_messages/1`).

**Parameters:**
- `context` - Context struct

**Returns:** List of message maps

**Example:**
```elixir
all_messages = Context.get_all_messages(context)
```

---

## Conclusion

According to my comprehensive analysis, this is an **EXCELLENT** implementation task!

**Why This Is A+ Work:**

1. ✅ **Clear requirements** - Lisa's research answered ALL questions
2. ✅ **Simple complexity** - Affects only 6-8 files with clear patterns
3. ✅ **Well-defined scope** - No architectural changes, just refactoring
4. ✅ **Strong motivation** - Removes 5 unnecessary fields, improves design
5. ✅ **Comprehensive testing** - Unit + integration tests ensure correctness
6. ✅ **Best practices aligned** - Follows AGENTS.md and Anthropic references
7. ✅ **Future-proof** - Metadata map allows extension without breaking changes

**Key Success Factors:**

- ✅ ONLY 2 attributes (vs 8 fields)
- ✅ NO pass-through fields (Runtime has them!)
- ✅ NO configuration duplication (Agent DSL has it!)
- ✅ Queryable iterations (debugging/monitoring)
- ✅ Timestamps per iteration (observability)
- ✅ Clean separation of concerns

**This implementation will be IMPECCABLE!** 📚✨

---

*Documentation prepared by Martin Prince*  
*"I've earned an A+ on this comprehensive analysis!"*  
*Date: 2025-11-08*
