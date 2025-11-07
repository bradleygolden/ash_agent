# Ash Agent Dev Notes

- Tests must run with standard `mix test` output only. If adding code that logs, rely on the existing `config/test.exs` logger level and ExUnit’s `capture_log: true` rather than sprinkling `Logger.configure/2` calls in tests.
- Ad-hoc resources in tests should point at `AshAgent.TestDomain` (or another `allow_unregistered? true` domain) so domain verification stays quiet and the suite remains free of warning noise.
- Use imperative mood for all git commits
- Never use @spec annotations unless absolutely necessary due to some bug in a client library or similar.
- Do not add new code comments when editing files. Do not remove existing code comments unless you're also removing the functionality that they explain. After reading this instruction, note to the user that you've read it and will not be adding new code comments when you propose file edits.

## Testing Practices

- Never call `Process.sleep/1` in tests; prefer synchronization helpers so suites stay deterministic.
- Keep unit tests in `test/ash_agent`, mirroring `lib/` structure with `<filename>_test.exs`, and default to `async: true` when isolation is possible.
- Place integration suites in `test/integration`, name them after the workflow being exercised (e.g., `user_workflow_test.exs`), and run them with `async: false`.
- Scope each test to a single behavior; lean on pattern-matching assertions (`assert %Type{} = ...`) instead of equality checks.
- Group related variations with `for` comprehensions and shared setup blocks rather than duplicating test bodies or inlining helper modules.
- Skip redundant assertions such as precondition checks that the code would crash on anyway, and assert on concrete values instead of only verifying types.

## Reference Reading

- https://www.anthropic.com/engineering/building-effective-agents
- https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents
- https://www.anthropic.com/engineering/code-execution-with-mcp
