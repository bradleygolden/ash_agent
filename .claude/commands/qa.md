# QA Command

Comprehensive quality assurance and validation for the AshAgent project.

## Purpose

The `/qa` command helps ensure code quality by:
- Running the complete test suite
- Performing static code analysis
- Checking code formatting compliance
- Validating type specifications
- Verifying consistency across documentation and code
- Removing non-critical code comments
- Identifying potential issues before deployment

## Usage

```
/qa
```

Run QA on specific files:

```
/qa lib/ash_agent.ex
```

## Execution Instructions

**IMPORTANT: Maximize parallel execution for speed!**

Many QA checks are independent and can run concurrently. Follow the parallelization strategy below.

### Parallelization Strategy

**Phase 1: Basic Checks (Run in Parallel)**
Execute all these Bash commands in a single message with multiple tool calls:
- `mix test --warnings-as-errors`
- `mix format --check-formatted`
- `mix credo --strict`
- `mix dialyzer`
- `mix compile --warnings-as-errors`
- `mix deps.unlock --check-unused`

**Phase 2: Analysis Subagents (Run in Parallel)**
Launch all these subagents in a single message with multiple Task calls:
- consistency-checker
- documentation-completeness-checker
- code-smell-checker
- dead-code-detector

**Phase 3: Cleanup (Sequential)**
- comment-scrubber (may need context from previous phases)

**Phase 4: Report (Sequential)**
- Generate comprehensive report

**Total phases: 4 (instead of 12 sequential steps)**

This reduces total QA time from ~X minutes to ~X/4 minutes!

### Detailed Steps

When this command is executed, you should:

1. **Set Up Tracking**: Use TodoWrite to track QA steps:
   - Run test suite
   - Check code formatting
   - Run Credo analysis
   - Run Dialyzer type checking
   - Check compilation warnings
   - Perform consistency checks
   - Check documentation completeness
   - Check for code smells and non-idiomatic patterns
   - Detect dead code
   - Scrub non-critical comments
   - Generate report

2. **Run All Basic Checks in Parallel** (Phase 1):
   - CRITICAL: Execute ALL five commands in a SINGLE message with multiple Bash tool calls
   - Run these concurrently:
     - `mix test` - Execute all tests, check for failures
     - `mix format --check-formatted` - Verify code formatting
     - `mix credo --strict` - Perform static code analysis
     - `mix dialyzer` - Check type specifications (first run builds PLT, slower)
     - `mix compile --warnings-as-errors` - Verify clean compilation
   - Wait for all results before proceeding
   - Report any issues found from all checks

3. **Run All Analysis Subagents in Parallel** (Phase 2):
   - CRITICAL: Launch ALL four subagents in a SINGLE message with multiple Task tool calls
   - Launch these concurrently:
     - consistency-checker subagent
     - documentation-completeness-checker subagent
     - code-smell-checker subagent (uses Skill tool internally)
     - dead-code-detector subagent
   - Wait for all subagent reports before proceeding
   - Collect all findings for final report

---

### Subagent Details (Launched in Phase 2)

The following provide details on what each subagent checks. All four subagents are launched concurrently in Phase 2.

#### Consistency Checker
- README.md examples match actual code usage
- Module documentation matches function signatures
- .formatter.exs exports match actual DSL functions
- Test examples align with documentation examples
- Configuration files reference correct modules/options
- DSL examples in lib/*/resource.ex match lib/*/dsl.ex

#### Documentation Completeness Checker
- All public modules have @moduledoc
- All public functions have @doc
- All public functions have @spec
- Complex functions have doctest examples
- Documentation quality (not just boilerplate)
- Callback and behaviour documentation

#### Code Smell Checker
- Elixir idioms (pattern matching, pipe operator, with statements)
- Code bloat and verbosity
- Function length and complexity (>20 lines flagged)
- Dependency usage best practices (using Skill tool for hex docs)
- Anti-patterns (unnecessary nesting, manual enum recreation, etc.)
- Code cleanliness (clean, concise, simple, explicit)

#### Dead Code Detector
- Unused private functions
- Unused modules
- Unreachable code
- Large blocks of commented-out code
- Functions with unused parameters

---

4. **Code Comment Scrubber** (Phase 3): Delegate to comment-scrubber subagent:
   - IMPORTANT: You MUST delegate this task to the comment-scrubber subagent
   - Explicitly state: "I'm going to use the comment-scrubber subagent to analyze code comments"
   - The subagent will scan lib/**/*.ex files and categorize comments as KEEP or REMOVE
   - Wait for the subagent's structured report with file:line references
   - Review the subagent's recommendations carefully
   - For each comment marked REMOVE:
     - Verify the recommendation by reading the file context yourself
     - Use Edit tool to remove the comment
   - Ask user confirmation before removing comments if there are more than 3 to remove
   - Include the subagent's analysis summary in your final QA report

5. **Generate Comprehensive Report** (Phase 4): Provide QA summary:
   - Overall status (pass/fail)
   - Summary of each check (tests, formatting, credo, dialyzer)
   - List of issues found with severity
   - Recommendations for fixes
   - Files or areas needing attention

## QA Checklist

Each QA run should verify:

- [ ] All tests pass (`mix test`)
- [ ] Code is properly formatted (`mix format --check-formatted`)
- [ ] No Credo issues at strict level (`mix credo --strict`)
- [ ] No Dialyzer type issues (`mix dialyzer`)
- [ ] Clean compilation with no warnings (`mix compile --warnings-as-errors`)
- [ ] Documentation is up to date
- [ ] Consistency checks pass (docs match code, examples match usage)
- [ ] All public APIs have @moduledoc, @doc, and @spec
- [ ] Code follows Elixir best practices (idiomatic, clean, concise, simple, explicit)
- [ ] Dependencies used idiomatically per their documentation
- [ ] No code smells (bloat, anti-patterns, unnecessary complexity)
- [ ] No unused code (dead functions, modules, unreachable code)
- [ ] No unnecessary comments (only critical comments remain)
- [ ] No TODO/FIXME comments without tracking numbers

## Quality Standards

### Test Requirements

- **All tests pass**: No failures or errors
- **Test coverage**: Core functionality should be tested
- **Test quality**: Tests should be meaningful and maintainable

### Code Quality Requirements

- **Formatting**: Follows `mix format` standards
- **Credo**: No critical or high severity issues
- **Dialyzer**: No type inconsistencies
- **Compilation**: No warnings

### Documentation Requirements

- **Moduledoc**: All modules have @moduledoc
- **Function docs**: Public functions have @doc
- **Examples**: Complex functions include doctest examples
- **Typespecs**: Public functions have @spec

## Tech Stack Context

- **Testing**: ExUnit (`mix test`)
- **Formatting**: Standard Elixir formatter (`mix format`)
- **Static Analysis**: Credo (`mix credo`)
- **Type Checking**: Dialyzer (`mix dialyzer`)
- **Elixir Version**: ~> 1.18

## Required Dependencies

Add these to mix.exs if not already present:

```elixir
defp deps do
  [
    {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
    {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
  ]
end
```

After adding dependencies, run:
```bash
mix deps.get
```

## Common Commands

```bash
# Run all tests
mix test

# Run tests with coverage (if excoveralls installed)
mix coveralls

# Check formatting
mix format --check-formatted

# Fix formatting
mix format

# Run Credo (standard)
mix credo

# Run Credo (strict mode)
mix credo --strict

# Run Dialyzer
mix dialyzer

# Compile with warnings as errors
mix compile --warnings-as-errors

# Clean build
mix clean && mix compile
```

## Consistency Check Guidelines

### What to Check

1. **Documentation vs Code**:
   - Module @moduledoc examples match actual usage
   - Function @doc descriptions match function signatures
   - README examples are executable and current

2. **DSL Definitions**:
   - Schema options in `dsl.ex` match what's used in examples
   - Formatter exports in `.formatter.exs` include all DSL functions
   - Resource extension examples match DSL examples

3. **Configuration Files**:
   - `mix.exs` dependencies referenced are actually used
   - Config files reference existing modules
   - Test configuration matches production setup

4. **Cross-References**:
   - Type definitions match usage across modules
   - Error messages reference actual functions/modules
   - Test fixtures match documented schemas

### How to Check

```elixir
# Manual verification process:
1. Read DSL example in lib/ash_agent/dsl.ex
2. Compare with example in lib/ash_agent/resource.ex @moduledoc
3. Compare with README.md examples
4. Check .formatter.exs exports include all functions shown
5. Verify test examples in test/ match documentation

# Automated checks (if available):
mix test.docs  # Run doctests to verify documentation examples
```

## Code Comment Scrubber Guidelines

### Comments to KEEP

**Critical Algorithm Explanations**:
```elixir
# Using binary search instead of linear for O(log n) performance
# on sorted datasets > 1000 items
def find_item(list, target) when length(list) > 1000 do
```

**Non-Obvious Business Logic**:
```elixir
# Temperature must be clamped to [0.0, 2.0] per Anthropic API requirements
# Values outside this range will cause 400 Bad Request errors
temperature = max(0.0, min(2.0, temp))
```

**TODO/FIXME with Tracking**:
```elixir
# TODO(#123): Implement streaming support once ReqLLM 2.0 is released
# FIXME(#456): Handle rate limiting - tracked in issue
```

### Comments to REMOVE

**Obvious Code Restatements**:
```elixir
# Set the temperature    <-- REMOVE
temperature = 0.7

# Call the function      <-- REMOVE
result = call_agent()
```

**Commented-Out Code**:
```elixir
# def old_implementation() do    <-- REMOVE
#   # ...
# end
```

**Developer Reminders**:
```elixir
# remember to update this later    <-- REMOVE
# note: this might not work         <-- REMOVE
# hmm, check if this is right       <-- REMOVE
```

**Redundant Section Markers**:
```elixir
# ================    <-- REMOVE
# Helper Functions
# ================
```

### Scrubbing Process

1. Use `Grep` to find all comment lines: `grep -n "^\s*#" lib/**/*.ex`
2. Read each file with comments
3. Categorize each comment (keep vs remove)
4. Use `Edit` to remove non-critical comments
5. Report files modified and comment count

## Issue Severity Levels

### Critical
- Test failures
- Compilation errors
- Dialyzer type errors that could cause runtime issues
- Documentation examples that don't work (misleading users)

### High
- Compilation warnings
- Credo consistency issues
- Missing documentation on public API
- Formatting violations
- Inconsistencies between code and documentation
- Inconsistencies in DSL definitions across files

### Medium
- Credo refactoring suggestions
- Minor documentation improvements
- Code readability issues
- Non-critical comments that should be removed
- Minor inconsistencies in examples

### Low
- Code style preferences
- Optional optimizations
- Nice-to-have improvements
- Harmless redundant comments

## Handling QA Failures

When QA checks fail:

1. **Document Issues**: Create todo list of all issues found
2. **Prioritize**: Address critical issues first
3. **Fix Systematically**: Resolve issues one at a time
4. **Re-run QA**: Verify fixes with another QA run
5. **Report**: Inform user of results and any remaining issues

## Integration with Other Commands

- Run after `/implement` to verify implementation quality
- May trigger additional `/implement` work to fix issues
- Results may inform future `/research` or `/plan` activities

## Key Principles

- **Comprehensive**: Run all quality checks, not just tests
- **Honest**: Report all issues found, even minor ones
- **Actionable**: Provide clear guidance on fixing issues
- **Standards**: Enforce consistent quality standards
- **Automation**: QA should be automated and repeatable

## Notes

- First Dialyzer run builds PLT cache (slow), subsequent runs are fast
- Some Credo rules can be configured in `.credo.exs` if needed
- QA should be run before considering work complete
- All QA checks should pass before committing or releasing code
- If tools are missing, offer to add them to mix.exs

## Output Format

Provide a structured report:

```
QA Report for AshAgent
=====================

✓ Tests: 12 passed, 0 failed
✓ Formatting: All files properly formatted
⚠ Credo: 2 issues found (1 high, 1 medium)
✗ Dialyzer: 1 type error found
✓ Compilation: Clean with no warnings
⚠ Consistency: 3 inconsistencies found
⚠ Documentation: 5 functions missing @spec, 2 modules missing @moduledoc
⚠ Code Smells: 4 issues found (2 bloated functions, 1 anti-pattern, 1 non-idiomatic usage)
⚠ Dead Code: 3 unused private functions, 1 unreachable code block
✓ Comments: 5 files cleaned, 12 comments removed

Issues Found:
-------------

HIGH - lib/ash_agent.ex:15
  [Credo.Check.Readability.ModuleDoc]
  Missing @moduledoc

HIGH - README.md:45 vs lib/ash_agent/resource.ex:27
  [Consistency]
  README example uses client("string") but DSL requires client "string", temperature: 0.7

MEDIUM - lib/ash_agent.ex:8
  [Credo.Check.Refactor.CyclomaticComplexity]
  Function has complexity of 15 (max 10)

MEDIUM - lib/ash_agent/runtime.ex:23
  [Comment Scrubber]
  Non-critical comment: "# This is obvious from the code"

HIGH - lib/ash_agent/schema.ex:45
  [Documentation Completeness]
  Public function convert/1 missing @spec

HIGH - lib/ash_agent/runtime.ex:92
  [Code Smell - Bloated Function]
  Function execute/2 is 45 lines (recommended: <20)
  Should be broken into: prepare_config/2, call_llm/1, finalize_result/1

MEDIUM - lib/ash_agent/converter.ex:30
  [Code Smell - Non-Idiomatic]
  Using nested if/else instead of pattern matching
  Refactor to use multi-clause function definitions

MEDIUM - lib/ash_agent/helpers.ex:78
  [Dead Code]
  Private function format_legacy/1 appears unused (0 callers)

ERROR - lib/ash_agent.ex:23
  [Dialyzer]
  Function hello/0 has no matching return type

Recommendations:
---------------
1. Add @moduledoc to AshAgent module
2. Update README.md example to match current DSL syntax
3. Refactor hello/0 to reduce complexity
4. Remove obvious comment in runtime.ex:23
5. Fix return type specification
6. Add @spec to schema.ex:45 convert/1
7. Remove or use helpers.ex:78 format_legacy/1

Overall Status: FAIL (7 issues to resolve)
```
