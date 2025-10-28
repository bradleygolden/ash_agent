# Plan Command

Create detailed implementation plans for features and changes in the AshAgent project.

## Purpose

The `/plan` command helps you design and document implementation approaches by:
- Breaking down complex features into manageable tasks
- Identifying technical decisions and trade-offs
- Creating reusable implementation roadmaps
- Ensuring thorough consideration before coding

## Usage

```
/plan "feature or change description"
```

## Examples

```
/plan "Add user authentication with JWT tokens"
/plan "Implement caching layer for API responses"
/plan "Refactor AshAgent module to support plugins"
```

## Execution Instructions

When this command is executed, you should:

1. **Understand Requirements**: Analyze the requested feature or change:
   - Clarify ambiguous requirements using AskUserQuestion
   - Identify scope and boundaries
   - Determine affected areas of the codebase
   - Consider integration points and dependencies

2. **Research Context**: Investigate the existing codebase:
   - Use Task tool with subagent_type=Explore to understand current architecture
   - Identify existing patterns and conventions to follow
   - Find similar implementations for reference
   - Check for relevant dependencies in mix.exs

3. **Design Solution**: Create a comprehensive implementation approach:
   - Break down into logical steps and phases
   - Identify technical decisions (which libraries, patterns, approaches)
   - Consider error handling and edge cases
   - Plan for testing and validation
   - Document architectural decisions and rationale

4. **Create Plan Document**: Write detailed plan to `.claude/docs/plans/[plan-name].md`:
   - Use kebab-case for filename (e.g., `user-authentication.md`)
   - Include all sections from the template below
   - Provide specific, actionable implementation steps
   - Include code examples where helpful

5. **Present Plan**: Show user the plan and:
   - Summarize key decisions and approach
   - Highlight any areas needing clarification
   - Provide path to full plan document
   - Ask for approval before implementation (if they want to proceed)

## Plan Document Format

Each plan document should follow this structure:

```markdown
# [Feature/Change Name]

**Created**: YYYY-MM-DD
**Status**: planned | in-progress | completed | abandoned

## Overview

[2-3 sentence summary of what this plan accomplishes]

## Requirements

- [Functional requirement 1]
- [Functional requirement 2]
- [Non-functional requirement 1]

## Current State

[Description of relevant current implementation, if any]

**Affected Files**:
- `lib/module.ex` - Current purpose
- `test/module_test.exs` - Current test coverage

## Proposed Solution

### Approach

[High-level description of the implementation approach and rationale]

### Architecture Decisions

**Decision 1**: [What was decided]
- **Rationale**: [Why this approach]
- **Trade-offs**: [What we're gaining/losing]
- **Alternatives considered**: [Other options and why they weren't chosen]

### Implementation Steps

#### Phase 1: [Phase Name]

1. **[Step Name]**
   - File: `lib/new_module.ex`
   - Action: [Specific implementation task]
   - Details: [Additional context or code patterns to follow]

2. **[Step Name]**
   - File: `test/new_module_test.exs`
   - Action: [Testing task]
   - Details: [Test cases to cover]

#### Phase 2: [Phase Name]

[Additional phases as needed...]

### Dependencies

**New Dependencies**:
- `{:library_name, "~> 1.0"}` - Purpose and reason for inclusion

**Existing Dependencies**:
- `:logger` - How it will be used

### Testing Strategy

1. **Unit Tests**: [What will be tested at unit level]
2. **Integration Tests**: [What will be tested at integration level]
3. **Edge Cases**: [Specific edge cases to cover]

### Error Handling

- [Scenario 1]: [How it will be handled]
- [Scenario 2]: [How it will be handled]

## Implementation Checklist

- [ ] Step 1 description
- [ ] Step 2 description
- [ ] Write tests
- [ ] Update documentation
- [ ] Run test suite
- [ ] Code quality checks

## Risks and Mitigations

- **Risk**: [Potential issue]
  - **Mitigation**: [How to address it]

## Future Considerations

[Ideas for future enhancements or related work]

## References

- [Link to related research documents]
- [Link to external documentation]
- [Link to relevant issues or discussions]
```

## Key Principles

- **Clarity**: Make implementation steps specific and actionable
- **Completeness**: Consider all aspects (testing, errors, edge cases)
- **Rationale**: Explain why decisions were made
- **Adaptability**: Design for change and future extensions
- **Standards**: Follow Elixir and project conventions

## Tech Stack Context

- **Language**: Elixir ~> 1.18
- **Build Tool**: Mix
- **Testing**: ExUnit (run with `mix test`)
- **Formatting**: Standard Elixir formatter
- **Common Patterns**: OTP, GenServer, Supervisor, etc.

## Integration with Other Commands

- Plans reference research from `/research` command
- Plans are executed by `/implement` command
- Quality is verified by `/qa` command

## Notes

- Plan documents are stored in `.claude/docs/plans/`
- Use kebab-case for filenames (e.g., `user-authentication.md`)
- Update plan status as implementation progresses
- Plans are living documents - update as you learn during implementation
- Don't start coding during planning - focus on design and decisions
