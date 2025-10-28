# Oneshot Command

Complete workflow combining research, planning, implementation, and QA in a single command.

## Purpose

The `/oneshot` command provides an end-to-end workflow that:
- Researches context and requirements
- Creates an implementation plan
- Executes the implementation
- Validates with comprehensive QA
- All in one seamless flow

## Usage

```
/oneshot "feature or task description"
```

## Examples

```
/oneshot "Add a greet/1 function that takes a name and returns a greeting"
/oneshot "Add logging support to the AshAgent module"
/oneshot "Create a configuration system using Application environment"
```

## When to Use Oneshot

Use `/oneshot` for:
- **Small to medium features**: Can be completed in one session
- **Clear requirements**: You know exactly what needs to be done
- **End-to-end delivery**: Want research, plan, code, and validation
- **Quick iterations**: Need rapid development cycles

Don't use `/oneshot` for:
- **Large, complex features**: Better to use separate `/plan` and `/implement`
- **Exploratory work**: Use `/research` first to understand the problem
- **Unclear requirements**: Clarify requirements before starting oneshot

## Execution Instructions

When this command is executed, you should:

1. **Set Up Tracking**: Use TodoWrite to track the complete workflow:
   - Research phase
   - Planning phase
   - Implementation phase
   - Testing phase
   - QA phase

2. **Research Phase**: Understand context and requirements:
   - Explore relevant existing code
   - Understand current architecture and patterns
   - Identify integration points and dependencies
   - Document findings (optional, brief inline research)
   - Mark research todo as completed

3. **Planning Phase**: Create implementation approach:
   - Design the solution approach
   - Break down into implementation steps
   - Identify technical decisions
   - Create abbreviated plan (inline or quick doc)
   - Present plan to user for confirmation
   - Mark planning todo as completed

4. **Implementation Phase**: Execute the plan:
   - Implement step by step
   - Follow Elixir conventions and project patterns
   - Write comprehensive tests
   - Add documentation and typespecs
   - Run `mix test` to verify tests pass
   - Run `mix format` to format code
   - Mark implementation todos as completed

5. **QA Phase**: Validate the implementation:
   - Run `mix test` - ensure all tests pass
   - Run `mix format --check-formatted` - verify formatting
   - Run `mix credo --strict` - check code quality (if available)
   - Run `mix dialyzer` - check types (if available)
   - Mark QA todo as completed

6. **Completion Report**: Provide comprehensive summary:
   - What was researched and learned
   - What was implemented
   - Test results
   - QA results
   - Any issues or follow-up items

## Workflow Phases

### Phase 1: Research (5-10% of time)

- Understand existing codebase relevant to task
- Identify patterns and conventions to follow
- Find related code for reference
- Brief, focused research - not exhaustive

### Phase 2: Plan (10-15% of time)

- Design solution approach
- Break into implementation steps
- Make key technical decisions
- Get user confirmation if needed

### Phase 3: Implement (60-70% of time)

- Write production code
- Write comprehensive tests
- Add documentation
- Format and organize code

### Phase 4: QA (15-20% of time)

- Run test suite
- Check code quality
- Verify formatting
- Type checking (if available)

## Quality Standards

All oneshot implementations must meet:

- **Tests**: Comprehensive ExUnit test coverage, all tests pass
- **Documentation**: @moduledoc and @doc for public functions
- **Typespecs**: @spec for public functions
- **Formatting**: Code formatted with `mix format`
- **Quality**: Passes Credo checks (if available)
- **Types**: Passes Dialyzer checks (if available)

## Tech Stack Context

- **Language**: Elixir ~> 1.18
- **Build Tool**: Mix
- **Testing**: ExUnit (`mix test`)
- **Formatting**: Standard formatter (`mix format`)
- **Quality Tools**: Credo, Dialyzer (when available)

## Example Oneshot Flow

```
User: /oneshot "Add a greet/1 function"

1. Research:
   - Review AshAgent module structure
   - Check existing function patterns
   - Identify test patterns used

2. Plan:
   - Add greet/1 function to AshAgent module
   - Take name parameter, return greeting string
   - Add documentation and typespec
   - Write tests with various inputs

3. Implement:
   - Add greet/1 function with doc and spec
   - Write ExUnit tests
   - Run mix test - ✓ all pass
   - Run mix format

4. QA:
   - mix test - ✓ pass
   - mix format --check-formatted - ✓ pass
   - mix credo --strict - ✓ pass
   - mix dialyzer - ✓ pass

5. Complete:
   - Feature delivered and validated
   - All quality checks pass
```

## Key Principles

- **Efficiency**: Move through phases systematically without delays
- **Quality**: Don't skip testing or QA to save time
- **Focus**: Stay on task, avoid scope creep
- **Communication**: Keep user informed with todo list updates
- **Completeness**: Deliver fully tested, documented, validated code

## Error Handling

If issues arise during oneshot:

- **Tests Fail**: Debug and fix before proceeding to QA
- **QA Issues**: Fix issues and re-run QA
- **Scope Too Large**: Suggest breaking into multiple tasks
- **Unclear Requirements**: Ask user for clarification

## Integration with Other Commands

Oneshot combines all workflow commands:
- Research (from `/research`)
- Planning (from `/plan`)
- Implementation (from `/implement`)
- QA validation (from `/qa`)

For larger or more complex work, use individual commands instead.

## Notes

- Oneshot is optimized for speed and efficiency
- Documentation created inline, not separate files (unless requested)
- Plan is abbreviated, focusing on key decisions
- All quality standards still apply
- Mark todos completed immediately after each phase
- Keep user informed throughout the process
- If work becomes too complex, suggest switching to separate workflows

## Success Criteria

A successful oneshot completion means:

✓ Feature/change fully implemented
✓ Comprehensive tests written and passing
✓ Code documented and formatted
✓ QA checks pass
✓ User informed of results
✓ Code ready to use/commit
