# Progressive Disclosure Guide

A comprehensive guide to managing large tool results and growing context in AshAgent.

## Table of Contents

1. [What is Progressive Disclosure?](#what-is-progressive-disclosure)
2. [Why Use Progressive Disclosure?](#why-use-progressive-disclosure)
3. [Architecture Overview](#architecture-overview)
4. [Hook-Based Approach](#hook-based-approach)
5. [Built-in Processors](#built-in-processors)
6. [Context Compaction Strategies](#context-compaction-strategies)
7. [Common Patterns & Cookbook](#common-patterns--cookbook)
8. [Advanced Patterns](#advanced-patterns)
9. [Performance Considerations](#performance-considerations)
10. [Troubleshooting](#troubleshooting)

---

## What is Progressive Disclosure?

Progressive Disclosure is a pattern for managing the growth of context in AI agent interactions. As agents iterate and accumulate tool results and conversation history, they face two key challenges:

1. **Token Budget Limits** - LLM providers impose maximum token limits per request
2. **Context Quality** - Too much information can dilute important details

Progressive Disclosure addresses these challenges through two techniques:

- **Result Processing** - Transform large tool results into compact representations
- **Context Compaction** - Remove or summarize old iterations to keep context focused

### The Problem

Without Progressive Disclosure, agents can quickly hit token limits:

```
Iteration 1:  5,000 tokens
Iteration 2: 12,000 tokens (added 7K of tool results)
Iteration 3: 25,000 tokens (added 13K more)
Iteration 4: 48,000 tokens (added 23K more)
Iteration 5: ERROR - Token limit exceeded!
```

### The Solution

With Progressive Disclosure:

```
Iteration 1:  5,000 tokens
Iteration 2:  8,000 tokens (tool results truncated)
Iteration 3: 10,000 tokens (old iterations removed)
Iteration 4: 11,000 tokens (continued compaction)
Iteration 5: 12,000 tokens (SUCCESS - under budget!)
```

---

## Why Use Progressive Disclosure?

### Token Efficiency

Reduce token usage by 50-70% in typical workflows:

- **Before:** 50,000 tokens for 10 iterations
- **After:** 15,000 tokens for 10 iterations
- **Savings:** 35,000 tokens (70%)

### Cost Reduction

Lower API costs with fewer tokens:

- **Claude Sonnet:** $3/1M input tokens
- **Savings:** $0.105 per 35K tokens saved
- **10,000 agent runs:** $1,050 saved

### Extended Conversations

Enable longer agent interactions:

- Without PD: ~10 iterations before token limit
- With PD: 50+ iterations possible

### Improved Focus

Keep agent context focused on recent, relevant information:

- Old iterations removed
- Tool results summarized
- Agent maintains coherence

---

## Architecture Overview

Progressive Disclosure integrates seamlessly with AshAgent's hook system:

```
┌─────────────────────────────────────────────────────────────┐
│                        AshAgent Runtime                     │
└─────────────────────────────────────────────────────────────┘
                              │
                              ├── Hook: prepare_tool_results
                              │   └──> Result Processors
                              │       ├── Truncate
                              │       ├── Summarize
                              │       └── Sample
                              │
                              ├── Hook: prepare_context
                              │   └──> Context Compaction
                              │       ├── Sliding Window
                              │       └── Token-Based
                              │
                              └── Hook: prepare_messages
                                  └──> Message Transformation
```

### Components

1. **Hooks** - Integration points in the agent execution flow
2. **Result Processors** - Transform individual tool results
3. **Context Helpers** - Manage iteration history
4. **ProgressiveDisclosure Module** - High-level convenience API

---

## Hook-Based Approach

Progressive Disclosure is implemented through AshAgent's hook system. Hooks are callbacks that intercept and transform data during agent execution.

### Hook Execution Points

```elixir
defmodule AshAgent.Runtime.Hooks do
  @callback prepare_tool_results(map()) :: {:ok, list()} | {:error, term()}
  @callback prepare_context(map()) :: {:ok, Context.t()} | {:error, term()}
  @callback prepare_messages(map()) :: {:ok, list()} | {:error, term()}
  @callback on_iteration_start(map()) :: {:ok, Context.t()} | {:error, term()}
  @callback on_iteration_complete(map()) :: {:ok, Context.t()} | {:error, term()}
end
```

### Minimal Hook Example

```elixir
defmodule MyApp.PDHooks do
  @behaviour AshAgent.Runtime.Hooks

  alias AshAgent.ProgressiveDisclosure

  def prepare_tool_results(%{results: results}) do
    # Truncate large results to 1000 bytes
    processed = ProgressiveDisclosure.process_tool_results(results,
      truncate: 1000
    )
    {:ok, processed}
  end

  def prepare_context(%{context: ctx}) do
    # Keep only last 5 iterations
    compacted = ProgressiveDisclosure.sliding_window_compact(ctx,
      window_size: 5
    )
    {:ok, compacted}
  end

  # Pass-through implementations for unused hooks
  def prepare_messages(%{messages: msgs}), do: {:ok, msgs}
  def on_iteration_start(%{context: ctx}), do: {:ok, ctx}
  def on_iteration_complete(%{context: ctx}), do: {:ok, ctx}
end
```

### Using Hooks in Your Agent

```elixir
defmodule MyAgent do
  use Ash.Resource,
    extensions: [AshAgent.Resource]

  agent do
    client "anthropic:claude-3-5-sonnet-20241022"
    hooks MyApp.PDHooks  # Enable Progressive Disclosure
    max_iterations 50
  end
end
```

---

## Built-in Processors

AshAgent provides three built-in result processors that can be used individually or composed together.

### Truncate Processor

Truncates large tool results to a specified size.

**When to use:**
- Tool returns very large text responses (logs, documents)
- You only need the beginning of the result
- Speed is important (truncation is fast)

**Options:**
- `:max_size` - Maximum size in bytes/items (default: 1000)
- `:marker` - Truncation indicator text (default: "... [truncated]")

**Example:**

```elixir
alias AshAgent.ResultProcessors.Truncate

results = [
  {"read_file", {:ok, large_file_contents}},
  {"query_db", {:ok, large_result_set}}
]

truncated = Truncate.process(results, max_size: 500, marker: "... (truncated)")
```

**Behavior:**

- Binaries (strings): Truncated by character count (UTF-8 safe)
- Lists: Truncated by item count
- Maps: Truncated by key count
- Error results: Preserved unchanged

**Example output:**

```elixir
# Before
{"read_file", {:ok, "This is a very long file with many lines...(10KB)"}}

# After
{"read_file", {:ok, "This is a very long file with many lines... [truncated]"}}
```

### Summarize Processor

Summarizes tool results using rule-based heuristics.

**When to use:**
- Tool returns structured data (lists, maps)
- You need to understand the shape/size without seeing all details
- Result type matters more than specific values

**Options:**
- `:strategy` - Summarization strategy: `:auto`, `:list`, `:map`, `:text` (default: `:auto`)
- `:sample_size` - Number of items to sample (default: 3)
- `:max_summary_size` - Maximum size of summary output (default: 500)

**Example:**

```elixir
alias AshAgent.ResultProcessors.Summarize

results = [
  {"list_users", {:ok, Enum.to_list(1..100)}}
]

summarized = Summarize.process(results, sample_size: 3)
```

**Behavior:**

- Auto-detects data type (list, map, text)
- Returns structured summary with metadata
- Includes representative samples

**Example output:**

```elixir
# Before
{"list_users", {:ok, [1, 2, 3, ..., 100]}}

# After
{"list_users", {:ok, %{
  type: "list",
  count: 100,
  sample: [1, 2, 3],
  summary: "List of 100 items (integers)"
}}}
```

### Sample Processor

Samples items from list-based tool results.

**When to use:**
- Tool returns long lists
- You only need a few examples
- Order matters (preserves order)

**Options:**
- `:sample_size` - Number of items to keep (default: 5)
- `:strategy` - Sampling strategy: `:first`, `:random`, `:distributed` (default: `:first`)

**Example:**

```elixir
alias AshAgent.ResultProcessors.Sample

results = [
  {"list_items", {:ok, Enum.to_list(1..1000)}}
]

sampled = Sample.process(results, sample_size: 5, strategy: :first)
```

**Behavior:**

- List results: Sampled by strategy
- Non-list results: Passed through unchanged
- Adds metadata about total count

**Example output:**

```elixir
# Before
{"list_items", {:ok, [1, 2, 3, ..., 1000]}}

# After
{"list_items", {:ok, %{
  items: [1, 2, 3, 4, 5],
  total_count: 1000,
  strategy: :first
}}}
```

---

## Context Compaction Strategies

Context compaction removes or transforms old iterations to keep context size manageable.

### Sliding Window

Keeps the last N iterations in full detail, removes older ones.

**When to use:**
- You have a fixed iteration history limit
- Recent interactions are most important
- Predictable memory usage is required

**Pros:**
- Simple and predictable
- Fast (no token counting needed)
- Configurable window size

**Cons:**
- Doesn't account for actual token usage
- May remove important context too early

**Example:**

```elixir
alias AshAgent.ProgressiveDisclosure

compacted = ProgressiveDisclosure.sliding_window_compact(context,
  window_size: 5
)

# Before: 10 iterations
# After:  5 iterations (last 5 kept)
```

**Configuration:**

```elixir
defmodule MyApp.SlidingWindowHooks do
  @behaviour AshAgent.Runtime.Hooks

  def prepare_context(%{context: ctx}) do
    compacted = ProgressiveDisclosure.sliding_window_compact(ctx,
      window_size: 5
    )
    {:ok, compacted}
  end
end
```

### Token-Based

Removes oldest iterations until context is under token budget.

**When to use:**
- You have strict token budget constraints
- Cost optimization is important
- Variable iteration sizes (some large, some small)

**Pros:**
- Respects actual token limits
- Cost-effective
- Adaptive to content size

**Cons:**
- Requires token estimation (approximate)
- Slightly slower (computes token counts)
- May remove important context if budget is too tight

**Example:**

```elixir
alias AshAgent.ProgressiveDisclosure

compacted = ProgressiveDisclosure.token_based_compact(context,
  budget: 50_000,
  threshold: 0.9
)

# Before: ~60,000 tokens
# After:  ~45,000 tokens (under budget)
```

**Configuration:**

```elixir
defmodule MyApp.TokenBudgetHooks do
  @behaviour AshAgent.Runtime.Hooks

  def prepare_context(%{context: ctx}) do
    compacted = ProgressiveDisclosure.token_based_compact(ctx,
      budget: 50_000
    )
    {:ok, compacted}
  end
end
```

### Comparison Table

| Strategy       | Best For                      | Pros                          | Cons                           |
|----------------|-------------------------------|-------------------------------|--------------------------------|
| Sliding Window | Fixed history, chat agents    | Simple, predictable, fast     | Ignores token count            |
| Token-Based    | Budget limits, cost control   | Respects limits, adaptive     | Approximate, requires compute  |

---

## Common Patterns & Cookbook

### Pattern 1: Truncate Large Tool Results

**Use case:** Agent uses tools that return large text outputs (logs, documents).

```elixir
defmodule MyApp.TruncateHooks do
  @behaviour AshAgent.Runtime.Hooks

  alias AshAgent.ProgressiveDisclosure

  def prepare_tool_results(%{results: results}) do
    processed = ProgressiveDisclosure.process_tool_results(results,
      truncate: 1000
    )
    {:ok, processed}
  end

  def prepare_context(%{context: ctx}), do: {:ok, ctx}
  def prepare_messages(%{messages: msgs}), do: {:ok, msgs}
  def on_iteration_start(%{context: ctx}), do: {:ok, ctx}
  def on_iteration_complete(%{context: ctx}), do: {:ok, ctx}
end
```

**Expected outcome:**
- Tool results limited to ~1000 bytes
- Agent maintains coherence with truncated results
- 50-70% token reduction for large results

### Pattern 2: Sliding Window for Chat Agents

**Use case:** Multi-turn conversation agent where only recent context matters.

```elixir
defmodule MyApp.ChatHooks do
  @behaviour AshAgent.Runtime.Hooks

  alias AshAgent.ProgressiveDisclosure

  def prepare_context(%{context: ctx}) do
    compacted = ProgressiveDisclosure.sliding_window_compact(ctx,
      window_size: 10
    )
    {:ok, compacted}
  end

  def prepare_tool_results(%{results: results}), do: {:ok, results}
  def prepare_messages(%{messages: msgs}), do: {:ok, msgs}
  def on_iteration_start(%{context: ctx}), do: {:ok, ctx}
  def on_iteration_complete(%{context: ctx}), do: {:ok, ctx}
end
```

**Expected outcome:**
- Context limited to last 10 turns
- Predictable memory usage
- Agent maintains short-term context

### Pattern 3: Token Budget Enforcement

**Use case:** Cost-sensitive application with strict token budget.

```elixir
defmodule MyApp.BudgetHooks do
  @behaviour AshAgent.Runtime.Hooks

  alias AshAgent.ProgressiveDisclosure

  @token_budget 50_000

  def prepare_context(%{context: ctx}) do
    compacted = ProgressiveDisclosure.token_based_compact(ctx,
      budget: @token_budget,
      threshold: 0.9
    )
    {:ok, compacted}
  end

  def prepare_tool_results(%{results: results}), do: {:ok, results}
  def prepare_messages(%{messages: msgs}), do: {:ok, msgs}
  def on_iteration_start(%{context: ctx}), do: {:ok, ctx}
  def on_iteration_complete(%{context: ctx}), do: {:ok, ctx}
end
```

**Expected outcome:**
- Context stays under 50K tokens
- Compaction triggers at 90% of budget
- Cost control with adaptive history

### Pattern 4: Combining Multiple Strategies

**Use case:** Maximum efficiency with both result processing and context compaction.

```elixir
defmodule MyApp.MaxEfficiencyHooks do
  @behaviour AshAgent.Runtime.Hooks

  alias AshAgent.ProgressiveDisclosure

  def prepare_tool_results(%{results: results}) do
    processed = ProgressiveDisclosure.process_tool_results(results,
      truncate: 1000,
      summarize: true,
      sample: 5
    )
    {:ok, processed}
  end

  def prepare_context(%{context: ctx}) do
    compacted = ProgressiveDisclosure.token_based_compact(ctx,
      budget: 50_000,
      threshold: 0.85
    )
    {:ok, compacted}
  end

  def prepare_messages(%{messages: msgs}), do: {:ok, msgs}
  def on_iteration_start(%{context: ctx}), do: {:ok, ctx}
  def on_iteration_complete(%{context: ctx}), do: {:ok, ctx}
end
```

**Expected outcome:**
- Maximum token efficiency (70-80% reduction)
- Tool results processed before adding to context
- Context compacted to stay under budget
- Agent maintains quality with processed data

---

## Advanced Patterns

### Custom Processors

Create your own result processor for domain-specific transformations.

```elixir
defmodule MyApp.CustomProcessor do
  @behaviour AshAgent.ResultProcessor

  @impl true
  def process(results, opts \\ []) do
    Enum.map(results, fn
      {name, {:ok, data}} = result ->
        if custom_condition?(data) do
          {name, {:ok, transform_data(data, opts)}}
        else
          result
        end

      error_result ->
        error_result
    end)
  end

  defp custom_condition?(data) do
    # Your logic here
  end

  defp transform_data(data, opts) do
    # Your transformation here
  end
end
```

### Conditional Processing

Process only certain tools based on name or result type.

```elixir
defmodule MyApp.ConditionalHooks do
  @behaviour AshAgent.Runtime.Hooks

  alias AshAgent.ResultProcessors.Truncate

  @large_result_tools ~w(read_file query_database fetch_logs)

  def prepare_tool_results(%{results: results}) do
    processed = Enum.map(results, fn
      {name, {:ok, data}} = result when name in @large_result_tools ->
        truncated = Truncate.process([result], max_size: 500)
        List.first(truncated)

      other_result ->
        other_result
    end)

    {:ok, processed}
  end
end
```

### Dynamic Configuration

Adjust Progressive Disclosure settings based on runtime conditions.

```elixir
defmodule MyApp.DynamicHooks do
  @behaviour AshAgent.Runtime.Hooks

  alias AshAgent.{Context, ProgressiveDisclosure}

  def prepare_context(%{context: ctx}) do
    utilization = Context.budget_utilization(ctx, 100_000)

    compacted = cond do
      utilization < 0.5 ->
        # Under 50% - no compaction needed
        ctx

      utilization < 0.8 ->
        # 50-80% - gentle compaction
        ProgressiveDisclosure.sliding_window_compact(ctx, window_size: 10)

      true ->
        # Over 80% - aggressive compaction
        ProgressiveDisclosure.token_based_compact(ctx, budget: 80_000)
    end

    {:ok, compacted}
  end
end
```

---

## Performance Considerations

### Processing Overhead

Progressive Disclosure adds minimal overhead:

- **Truncation:** < 1ms per result (very fast)
- **Summarization:** 1-5ms per result (moderate)
- **Sampling:** < 1ms per result (very fast)
- **Context compaction:** 10-50ms (depends on iteration count)

### Skip-If-Small Optimization

The `process_tool_results` pipeline automatically skips processing if all results are under the threshold:

```elixir
# This automatically skips if all results < 1000 bytes
processed = ProgressiveDisclosure.process_tool_results(results,
  truncate: 1000,
  skip_small: true  # default
)
```

Benefits:
- No overhead for small results
- Only processes when needed
- Maintains performance

### Token Estimation Accuracy

Token estimation uses a heuristic (~4 chars per token) and is approximate:

- **Accuracy:** ±20-30% of actual count
- **Fast:** No API calls required
- **Good enough:** For budget checking, estimates work well

For exact token counts, use your provider's tokenizer:

```elixir
# Example with Anthropic
{:ok, count} = Anthropic.count_tokens(messages)
```

### Memory Usage

Context compaction reduces memory footprint:

- **Before:** 10 iterations @ 5KB each = 50KB
- **After:** 3 iterations @ 5KB each = 15KB
- **Savings:** 35KB (70%)

---

## Troubleshooting

### Problem: Over-truncation removes critical information

**Symptoms:**
- Agent asks for the same information repeatedly
- Agent says "I don't have enough information"
- Tool results are too small to be useful

**Solution:**
Increase the truncation threshold or disable truncation for specific tools:

```elixir
# Option 1: Increase threshold
processed = ProgressiveDisclosure.process_tool_results(results,
  truncate: 5000  # Increased from 1000
)

# Option 2: Conditional processing
def prepare_tool_results(%{results: results}) do
  processed = Enum.map(results, fn
    {name, _result} = entry when name == "critical_tool" ->
      entry  # Don't process critical tool

    other ->
      Truncate.process([other], max_size: 1000) |> List.first()
  end)

  {:ok, processed}
end
```

### Problem: Agent loses context coherence

**Symptoms:**
- Agent forgets previous interactions
- Agent contradicts itself
- Agent asks questions it already asked

**Solution:**
Increase sliding window size or use less aggressive compaction:

```elixir
# Option 1: Larger window
compacted = ProgressiveDisclosure.sliding_window_compact(ctx,
  window_size: 10  # Increased from 5
)

# Option 2: Higher token budget
compacted = ProgressiveDisclosure.token_based_compact(ctx,
  budget: 100_000  # Increased from 50_000
)
```

### Problem: Token budget still exceeded

**Symptoms:**
- Agent hits token limit despite PD
- Token estimates show under budget, but API rejects request
- Compaction not removing enough iterations

**Solution:**
Use more aggressive compaction or combine strategies:

```elixir
# More aggressive token budget
compacted = ProgressiveDisclosure.token_based_compact(ctx,
  budget: 40_000,  # Reduced to leave buffer
  threshold: 0.8   # Trigger earlier
)

# Or combine with result processing
def prepare_tool_results(%{results: results}) do
  ProgressiveDisclosure.process_tool_results(results,
    truncate: 500,    # More aggressive
    summarize: true   # Add summarization
  )
end
```

### Problem: Processing is too slow

**Symptoms:**
- Noticeable delay in agent responses
- High CPU usage during hook execution
- Telemetry shows long processing times

**Solution:**
Use skip optimization and selective processing:

```elixir
# Enable skip optimization (default, but be explicit)
processed = ProgressiveDisclosure.process_tool_results(results,
  truncate: 1000,
  skip_small: true  # Skip if all results are small
)

# Or selectively process only large tools
@large_tools ~w(fetch_logs query_database)

def prepare_tool_results(%{results: results}) do
  processed = Enum.map(results, fn
    {name, _} = result when name in @large_tools ->
      Truncate.process([result], max_size: 1000) |> List.first()

    other ->
      other  # Skip processing small tools
  end)

  {:ok, processed}
end
```

### Problem: Summarization loses important details

**Symptoms:**
- Agent doesn't see specific values in summarized results
- Agent says "I need more detail"
- Summaries are too generic

**Solution:**
Increase sample size or use truncation instead:

```elixir
# Option 1: Larger samples
summarized = Summarize.process(results,
  sample_size: 10  # Increased from 3
)

# Option 2: Use truncation instead (preserves detail)
truncated = Truncate.process(results,
  max_size: 2000
)
```

### Problem: Telemetry events not appearing

**Symptoms:**
- No PD telemetry in logs
- Can't measure PD effectiveness
- Monitoring not working

**Solution:**
Attach telemetry handlers:

```elixir
:telemetry.attach_many(
  "progressive-disclosure-handler",
  [
    [:ash_agent, :progressive_disclosure, :process_results],
    [:ash_agent, :progressive_disclosure, :sliding_window],
    [:ash_agent, :progressive_disclosure, :token_based]
  ],
  fn event_name, measurements, metadata, _config ->
    Logger.info("PD Event: #{inspect(event_name)}")
    Logger.info("Measurements: #{inspect(measurements)}")
    Logger.info("Metadata: #{inspect(metadata)}")
  end,
  nil
)
```

---

## Additional Resources

- [AshAgent Documentation](https://hexdocs.pm/ash_agent)
- [Result Processors API](https://hexdocs.pm/ash_agent/AshAgent.ResultProcessors.html)
- [Context Helpers API](https://hexdocs.pm/ash_agent/AshAgent.Context.html)
- [ProgressiveDisclosure API](https://hexdocs.pm/ash_agent/AshAgent.ProgressiveDisclosure.html)
- [Hook System Guide](https://hexdocs.pm/ash_agent/AshAgent.Runtime.Hooks.html)

---

*Last updated: 2025-11-10*
