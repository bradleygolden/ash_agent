# Implement Command

Execute implementation plans with verification and quality checks for the AshAgent project.

## Purpose

The `/implement` command helps you execute planned features by:
- Following detailed implementation plans systematically
- Tracking progress through implementation steps
- Verifying work with tests and quality checks
- Ensuring completeness before marking work as done

## Usage

```
/implement "plan-name"
```

Or for ad-hoc implementations:

```
/implement "quick description of what to implement"
```

## Examples

```
/implement "user-authentication"
/implement "Add logging to AshAgent.hello/0 function"
```

## Execution Instructions

When this command is executed, you should:

1. **Load Plan**: Locate and read the implementation plan:
   - If plan name provided: Read `.claude/docs/plans/[plan-name].md`
   - If description provided: Create a quick inline plan
   - If plan not found: Ask user to clarify or run `/plan` first

2. **Set Up Tracking**: Use TodoWrite to create implementation checklist:
   - Extract steps from the plan document
   - Create todo items for each implementation phase/step
   - Include testing and verification steps
   - Add quality check steps at the end

3. **Implement Systematically**: Execute the plan step by step:
   - Mark current step as in_progress
   - Implement the specific step following the plan
   - Follow Elixir conventions and project patterns
   - Include appropriate documentation and typespecs
   - Complete current step before moving to next
   - Mark each step as completed when done

4. **Write Tests**: Ensure comprehensive test coverage:
   - Write ExUnit tests for new functionality
   - Follow existing test patterns in the project
   - Cover happy path, edge cases, and error conditions
   - Run `mix test` after writing tests to verify they pass

5. **Verify Implementation**: Run verification checks:
   - Execute `mix test` to ensure all tests pass
   - Run `mix format` to format code
   - Check that implementation matches plan requirements
   - Update plan document status to "completed"

6. **Report Completion**: Provide summary to user:
   - List what was implemented
   - Show test results
   - Note any deviations from plan (with rationale)
   - Suggest next steps or related improvements

## Implementation Guidelines

### Code Quality Standards

- **Documentation**: Add @moduledoc and @doc for all public functions
- **Typespecs**: Include @spec for public functions
- **Naming**: Follow Elixir naming conventions (snake_case for functions/variables)
- **Formatting**: Use `mix format` before completion
- **Error Handling**: Handle errors appropriately with {:ok, result} | {:error, reason} patterns

### Testing Standards

- **Coverage**: Test all public functions
- **Patterns**: Use ExUnit patterns (describe, test, setup)
- **Assertions**: Use appropriate assertions (assert, refute, assert_raise)
- **Documentation**: Include doctest examples in @doc where appropriate

### Elixir Patterns

- **Modules**: Organize code in well-named modules
- **Functions**: Keep functions small and focused
- **Pattern Matching**: Use pattern matching idiomatically
- **Pipes**: Use pipe operator |> for data transformations
- **Guards**: Use guards for type checking when appropriate

## Workflow Steps

1. **Read Plan**
   ```elixir
   # Load and review the implementation plan
   ```

2. **Create Todo List**
   ```elixir
   # Use TodoWrite to track all steps from plan
   ```

3. **Implement Each Step**
   ```elixir
   # Follow plan systematically, one step at a time
   # Mark each todo in_progress -> completed
   ```

4. **Write Tests**
   ```elixir
   # Create comprehensive test coverage
   # Run: mix test
   ```

5. **Format Code**
   ```elixir
   # Run: mix format
   ```

6. **Update Plan Status**
   ```elixir
   # Edit plan document to mark as completed
   ```

7. **Summary Report**
   ```elixir
   # Provide completion summary to user
   ```

## Tech Stack Context

- **Language**: Elixir ~> 1.18
- **Build Tool**: Mix
- **Testing**: ExUnit with `mix test`
- **Formatting**: `mix format`
- **Project Structure**:
  - `lib/` - Application code
  - `test/` - Test files
  - `mix.exs` - Project configuration and dependencies

## Common Commands

```bash
# Run tests
mix test

# Run specific test file
mix test test/module_test.exs

# Run tests with verbose output
mix test --trace

# Format code
mix format

# Compile project
mix compile
```

## Error Handling

If implementation encounters issues:

- **Tests Fail**: Debug the implementation, don't just mark as complete
- **Missing Dependencies**: Add to mix.exs and run `mix deps.get`
- **Plan Unclear**: Ask user for clarification or update plan
- **Scope Change**: Discuss with user and update plan document

## Integration with Other Commands

- Implements plans created by `/plan` command
- Uses research from `/research` command as reference
- Quality verified by `/qa` command after completion

## Key Principles

- **Systematic**: Follow plan step by step, don't skip ahead
- **Quality**: Write tests and documentation as you go
- **Completeness**: Don't mark work done until verified
- **Communication**: Keep todo list updated for transparency
- **Standards**: Follow Elixir and project conventions consistently

## Notes

- Always update plan document status when implementation is complete
- Mark todos completed immediately after finishing each step
- Run tests frequently during implementation to catch issues early
- If plan needs adjustment during implementation, update the plan document
- Leave code better than you found it (refactor when appropriate)
