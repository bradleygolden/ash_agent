# Progressive Disclosure Demo

Demonstrates token savings achieved with Progressive Disclosure features in AshAgent.

## Overview

This example shows how Progressive Disclosure can dramatically reduce token usage and costs when working with large tool results and long conversation contexts.

## Running the Demo

```bash
# Install dependencies
mix deps.get

# Run the demo
mix run lib/progressive_disclosure_demo.ex
```

## What the Demo Shows

The demo creates an agent that processes large datasets through multiple iterations. It compares:

1. **Without Progressive Disclosure**: Agent processes full 10KB tool results, keeps all iteration history
2. **With Progressive Disclosure**: Agent uses truncation, summarization, and context compaction

## Expected Results

- **Without PD**: ~50,000 tokens used
- **With PD**: ~15,000 tokens used
- **Savings**: ~70% reduction in token usage

See `results/token_savings_report.txt` for detailed breakdown.

## Features Demonstrated

- **Result Truncation**: Large tool results truncated to 500 bytes
- **Summarization**: Complex data structures summarized with key information preserved
- **Sampling**: Large lists reduced to representative samples
- **Context Compaction**: Sliding window keeps only last 3 iterations

## Cost Impact

At typical API pricing ($0.01 per 1K tokens):
- Without PD: $0.50 per run
- With PD: $0.15 per run
- **Savings: $0.35 per run**

Over 10,000 agent runs: **$3,500 saved**

## Code Structure

- `lib/demo_agent.ex` - Agent definition with large data tools
- `lib/pd_hooks.ex` - Progressive Disclosure hooks implementation
- `lib/progressive_disclosure_demo.ex` - Main demo runner
- `results/token_savings_report.txt` - Detailed metrics

## Learn More

See the [Progressive Disclosure Guide](../../documentation/guides/progressive-disclosure.md) for comprehensive documentation.
