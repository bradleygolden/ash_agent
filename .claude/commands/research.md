# Research Command

Comprehensive codebase documentation and exploration for the AshAgent project.

## Purpose

The `/research` command helps you understand and document your Elixir codebase by:
- Answering specific questions about code structure and implementation
- Exploring patterns and architectural decisions
- Documenting findings for future reference
- Building institutional knowledge about the project

## Usage

```
/research "your question or topic"
```

## Examples

```
/research "How does the AshAgent module work?"
/research "What testing patterns are used in this project?"
/research "Explain the project structure and dependencies"
```

## Execution Instructions

When this command is executed, you should:

1. **Understand the Question**: Parse the user's research query to identify:
   - Specific modules, functions, or patterns to investigate
   - Scope of the research (single file, module, or entire codebase)
   - Type of information needed (how it works, why it's designed this way, what it does)

2. **Explore Thoroughly**: Use the appropriate exploration strategy:
   - For specific questions: Use Grep to find relevant code, then Read files
   - For broad questions: Use Task tool with subagent_type=Explore for comprehensive analysis
   - For architectural questions: Examine module structure, dependencies, and relationships

3. **Analyze Findings**:
   - Examine the code to understand implementation details
   - Identify patterns, conventions, and design decisions
   - Look for related tests to understand intended behavior
   - Check mix.exs for relevant dependencies

4. **Document Results**: Create a dated research document:
   - Filename format: `.claude/docs/research/YYYY-MM-DD-topic.md`
   - Include clear explanations with code references (file:line format)
   - Add examples and relevant code snippets
   - Document any questions or areas for future investigation

5. **Present Summary**: Provide the user with:
   - Concise answer to their question
   - Location of the full research document
   - Key insights or important findings
   - Suggestions for related areas to explore

## Research Documentation Format

Each research document should include:

```markdown
# [Topic/Question]

**Date**: YYYY-MM-DD
**Question**: [Original research question]

## Summary

[Brief 2-3 sentence overview of findings]

## Findings

### [Key Area 1]

[Detailed explanation with code references]

```elixir
# Relevant code examples
```

### [Key Area 2]

[Additional findings...]

## Related Files

- `lib/file.ex:123` - Description
- `test/file_test.exs:45` - Description

## Open Questions

- [Any unresolved questions or areas for future investigation]

## References

- [Links to documentation, issues, or external resources]
```

## Key Principles

- **Thoroughness**: Explore code deeply to provide comprehensive answers
- **Accuracy**: Include specific file and line references
- **Context**: Explain not just what the code does, but why and how
- **Organization**: Use dated files to track research chronologically
- **Reusability**: Document findings so they're useful for future reference

## Tech Stack Context

- **Language**: Elixir ~> 1.18
- **Build Tool**: Mix
- **Testing**: ExUnit (run with `mix test`)
- **Formatting**: Standard Elixir formatter

## Notes

- Research documents are stored in `.claude/docs/research/`
- Use ISO date format (YYYY-MM-DD) in filenames for chronological sorting
- Include code snippets to illustrate findings
- Cross-reference related research documents when applicable
