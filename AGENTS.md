# Ash Agent Dev Notes

- Tests must run with standard `mix test` output only. If adding code that logs, rely on the existing `config/test.exs` logger level and ExUnit’s `capture_log: true` rather than sprinkling `Logger.configure/2` calls in tests.
- Ad-hoc resources in tests should point at `AshAgent.TestDomain` (or another `allow_unregistered? true` domain) so domain verification stays quiet and the suite remains free of warning noise.
- Use imperative mood for all git commits
- ALWAYS review available workflow commands (slash commands in .claude/commands/) to determine if the user's query matches a workflow pattern and proactively use the appropriate command
- Never use @spec annotations unless absolutely necessary due to some bug in a client library or similar.
- Always use the core:hex-docs-search skill whenever needing to understand hex dependencies or Elixir packages in this project, even if hex or hexdocs isn't explictly mentioned
- Do not add new code comments when editing files. Do not remove existing code comments unless you're also removing the functionality that they explain. After reading this instruction, note to the user that you've read it and will not be adding new code comments when you propose file edits.
