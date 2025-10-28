# AshAgent Development Workflows

Complete guide to using workflow commands for the AshAgent project.

## Overview

This document describes the workflow commands available for systematic development of the AshAgent project. These commands provide structured approaches to research, planning, implementation, and quality assurance.

## Available Commands

### `/research` - Codebase Documentation & Exploration

Investigate and document your codebase to answer questions and build understanding.

**Usage:**
```
/research "your question or topic"
```

**Examples:**
```
/research "How does the AshAgent module work?"
/research "What testing patterns are used in this project?"
/research "Explain the project structure"
```

**When to use:**
- Understanding existing code or patterns
- Answering specific questions about implementation
- Building institutional knowledge
- Before planning new features

**Output:**
- Research document: `.claude/docs/research/YYYY-MM-DD-topic.md`
- Organized chronologically by date

---

### `/plan` - Create Implementation Plans

Design detailed implementation approaches for features and changes.

**Usage:**
```
/plan "feature or change description"
```

**Examples:**
```
/plan "Add user authentication with JWT tokens"
/plan "Implement caching layer for API responses"
/plan "Refactor AshAgent module to support plugins"
```

**When to use:**
- Before implementing new features
- When making significant changes
- To design and document approach
- To identify technical decisions

**Output:**
- Plan document: `.claude/docs/plans/[plan-name].md`
- Includes architecture decisions, steps, testing strategy

---

### `/implement` - Execute Plans

Systematically implement features following plans with verification.

**Usage:**
```
/implement "plan-name"
/implement "quick task description"
```

**Examples:**
```
/implement "user-authentication"
/implement "Add logging to AshAgent.hello/0 function"
```

**When to use:**
- After creating a plan with `/plan`
- For ad-hoc implementations (creates inline plan)
- When ready to write code

**Process:**
1. Loads implementation plan
2. Creates todo list from plan steps
3. Implements step by step
4. Writes tests
5. Runs verification

**Quality checks:**
- `mix test` - all tests pass
- `mix format` - code formatted
- Plan status updated to "completed"

---

### `/qa` - Quality Assurance

Comprehensive quality validation with multiple checks.

**Usage:**
```
/qa
/qa lib/ash_agent.ex
```

**When to use:**
- After implementation is complete
- Before committing code
- When validating code quality
- Regular quality checks

**Checks performed:**
1. **Tests**: `mix test` - all tests pass
2. **Formatting**: `mix format --check-formatted` - proper formatting
3. **Credo**: `mix credo --strict` - code quality analysis
4. **Dialyzer**: `mix dialyzer` - type checking
5. **Compilation**: `mix compile --warnings-as-errors` - clean compilation

**Output:**
- Comprehensive QA report
- Issues categorized by severity
- Actionable recommendations

---

### `/oneshot` - Complete Workflow

End-to-end workflow from research to QA in one command.

**Usage:**
```
/oneshot "feature or task description"
```

**Examples:**
```
/oneshot "Add a greet/1 function that takes a name"
/oneshot "Add logging support to AshAgent module"
```

**When to use:**
- Small to medium features
- Clear requirements
- Need rapid iteration
- Want complete delivery

**Process:**
1. Research (understand context)
2. Plan (design approach)
3. Implement (write code and tests)
4. QA (validate quality)
5. Report (complete summary)

**Note:** For large or complex features, use individual commands instead.

---

## Workflow Patterns

### Pattern 1: Full Workflow (Large Features)

For significant features requiring careful design:

```
1. /research "understand existing implementation"
2. /plan "design the new feature"
3. /implement "feature-name"
4. /qa
```

### Pattern 2: Quick Implementation (Small Changes)

For straightforward changes:

```
1. /implement "add simple function"
2. /qa
```

### Pattern 3: Oneshot (Medium Features)

For moderate complexity with clear requirements:

```
1. /oneshot "add feature X"
```

### Pattern 4: Iterative Development

For exploratory or evolving features:

```
1. /research "explore current implementation"
2. /plan "initial design"
3. /implement "phase-1"
4. /qa
5. /research "learn from phase 1"
6. /plan "phase-2 improvements"
7. /implement "phase-2"
8. /qa
```

## Project Context

### Tech Stack

- **Language**: Elixir ~> 1.18
- **Build Tool**: Mix
- **Testing**: ExUnit (`mix test`)
- **Formatting**: Standard Elixir formatter (`mix format`)

### Quality Tools

Install recommended quality tools:

```elixir
# Add to mix.exs deps/0
{:credo, "~> 1.7", only: [:dev, :test], runtime: false},
{:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
```

Then run:
```bash
mix deps.get
```

### Project Structure

```
ash_agent/
├── .claude/
│   ├── commands/          # Workflow command definitions
│   ├── docs/
│   │   ├── research/      # Research documents (dated)
│   │   └── plans/         # Implementation plans
│   └── WORKFLOWS.md       # This file
├── lib/
│   └── ash_agent.ex       # Application code
├── test/
│   └── ash_agent_test.exs # Tests
└── mix.exs                # Project configuration
```

### Common Commands

```bash
# Testing
mix test                   # Run all tests
mix test --trace          # Verbose test output

# Code Quality
mix format                # Format code
mix format --check-formatted  # Check formatting
mix credo                 # Code analysis
mix credo --strict        # Strict analysis
mix dialyzer              # Type checking

# Build
mix compile               # Compile project
mix compile --warnings-as-errors  # Strict compilation
mix clean                 # Clean build artifacts
```

## Quality Standards

All code must meet these standards:

### Documentation
- [ ] @moduledoc on all modules
- [ ] @doc on all public functions
- [ ] Examples in documentation where helpful

### Type Specifications
- [ ] @spec on all public functions
- [ ] Use appropriate type definitions
- [ ] Pass Dialyzer type checking

### Testing
- [ ] ExUnit tests for all public functions
- [ ] Test happy path, edge cases, errors
- [ ] All tests pass
- [ ] Follow existing test patterns

### Code Quality
- [ ] Formatted with `mix format`
- [ ] Passes `mix credo --strict`
- [ ] Follows Elixir conventions
- [ ] Clean compilation (no warnings)

### Elixir Conventions
- [ ] snake_case for functions and variables
- [ ] PascalCase for modules
- [ ] Use pattern matching idiomatically
- [ ] Use pipe operator for transformations
- [ ] Return {:ok, result} | {:error, reason} for operations that can fail

## Tips and Best Practices

### Research Tips
- Use Task tool with subagent_type=Explore for broad questions
- Include code references (file:line format) in documentation
- Document not just what, but why and how
- Cross-reference related research documents

### Planning Tips
- Break complex features into phases
- Document architectural decisions and rationale
- Consider testing strategy upfront
- Include error handling approach
- Plan for future extensibility

### Implementation Tips
- Follow the plan systematically
- Write tests as you implement features
- Run tests frequently during development
- Keep functions small and focused
- Update plan if you discover issues

### QA Tips
- Run QA before considering work complete
- First Dialyzer run is slow (builds PLT), later runs are fast
- Address critical issues before medium/low priority
- Re-run QA after fixing issues
- All checks should pass before committing

### General Tips
- Use TodoWrite to track progress
- Mark todos completed immediately after finishing
- Keep user informed throughout workflow
- Update plan status when implementation completes
- Follow project conventions consistently

## Customization

These workflow commands are customized for the AshAgent project with:

- **Documentation Location**: `.claude/` directory
- **Research Organization**: By date (YYYY-MM-DD-topic.md)
- **Testing Approach**: ExUnit standard (`mix test`)
- **QA Tools**: Credo, Dialyzer, mix format checks

You can further customize by editing command files in `.claude/commands/`.

## Getting Started

1. **Install Quality Tools** (recommended):
   ```bash
   # Add to mix.exs and run
   mix deps.get
   ```

2. **Try a Simple Workflow**:
   ```
   /research "What does AshAgent.hello/0 do?"
   ```

3. **Implement a Small Feature**:
   ```
   /oneshot "Add a goodbye/0 function that returns :goodbye"
   ```

4. **Run QA**:
   ```
   /qa
   ```

## Troubleshooting

### "Plan not found"
Run `/plan` first to create the implementation plan, or use `/implement` with a description for ad-hoc implementation.

### "Tests failed"
Debug the implementation before marking work complete. Check test output for specific failures.

### "Credo/Dialyzer not available"
Add dependencies to mix.exs:
```elixir
{:credo, "~> 1.7", only: [:dev, :test], runtime: false},
{:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
```

### "QA taking too long"
First Dialyzer run builds PLT cache (slow). Subsequent runs are much faster. You can skip Dialyzer for quick checks if needed.

## Support

For issues or questions:
- Check command documentation in `.claude/commands/`
- Review this WORKFLOWS.md guide
- Examine existing research and plans for examples

## Version

**Workflows Version**: 1.0
**Generated**: 2025-10-28
**Project**: AshAgent
**Elixir Version**: ~> 1.18

---

Happy coding! These workflows are designed to help you build high-quality Elixir code systematically.
