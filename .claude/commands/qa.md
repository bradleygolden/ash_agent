# QA Command

Comprehensive quality assurance and validation for the AshAgent project.

## Purpose

The `/qa` command helps ensure code quality by:
- Running the complete test suite
- Performing static code analysis
- Checking code formatting compliance
- Validating type specifications
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

When this command is executed, you should:

1. **Set Up Tracking**: Use TodoWrite to track QA steps:
   - Run test suite
   - Check code formatting
   - Run Credo analysis
   - Run Dialyzer type checking
   - Report results

2. **Run Test Suite**: Execute ExUnit tests:
   - Run `mix test` to execute all tests
   - Check for test failures or errors
   - Report test coverage and results
   - If tests fail: investigate and report issues

3. **Check Formatting**: Verify code formatting:
   - Run `mix format --check-formatted`
   - If formatting issues found: either fix with `mix format` or report to user
   - Ensure all Elixir files follow standard formatting

4. **Run Credo**: Perform static code analysis:
   - Run `mix credo --strict` for comprehensive analysis
   - Report any issues found (design, readability, refactoring opportunities)
   - Categorize issues by severity
   - Note: Add `{:credo, "~> 1.7", only: [:dev, :test], runtime: false}` to mix.exs if not present

5. **Run Dialyzer**: Check type specifications:
   - Run `mix dialyzer` for type checking
   - Report type inconsistencies or missing specs
   - Note: Add `{:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}` to mix.exs if not present
   - First run may be slow (builds PLT), subsequent runs are faster

6. **Compile Check**: Verify clean compilation:
   - Run `mix compile --warnings-as-errors`
   - Ensure no compilation warnings or errors
   - Report any issues found

7. **Generate Report**: Provide comprehensive QA summary:
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
- [ ] No TODO/FIXME comments in critical code

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

## Issue Severity Levels

### Critical
- Test failures
- Compilation errors
- Dialyzer type errors that could cause runtime issues

### High
- Compilation warnings
- Credo consistency issues
- Missing documentation on public API
- Formatting violations

### Medium
- Credo refactoring suggestions
- Minor documentation improvements
- Code readability issues

### Low
- Code style preferences
- Optional optimizations
- Nice-to-have improvements

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

Issues Found:
-------------

HIGH - lib/ash_agent.ex:15
  [Credo.Check.Readability.ModuleDoc]
  Missing @moduledoc

MEDIUM - lib/ash_agent.ex:8
  [Credo.Check.Refactor.CyclomaticComplexity]
  Function has complexity of 15 (max 10)

ERROR - lib/ash_agent.ex:23
  [Dialyzer]
  Function hello/0 has no matching return type

Recommendations:
---------------
1. Add @moduledoc to AshAgent module
2. Refactor hello/0 to reduce complexity
3. Fix return type specification

Overall Status: FAIL (3 issues to resolve)
```
