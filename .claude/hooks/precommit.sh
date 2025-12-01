#!/bin/bash
set -euo pipefail

# Read the JSON input from stdin
INPUT=$(cat)

# Extract the bash command being executed
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Check if this is a git commit command (handles standalone, with flags, or chained)
if [[ "$COMMAND" =~ git[[:space:]]+commit ]]; then
  cd "$CLAUDE_PROJECT_DIR" || exit 2

  # Check if there are staged files
  STAGED_FILES=$(git diff --cached --name-only 2>/dev/null || true)

  if [[ -z "$STAGED_FILES" ]]; then
    exit 0
  fi

  echo "Running precommit checks..." >&2

  if ! mix precommit; then
    echo "Precommit checks failed" >&2
    exit 2
  fi

  echo "Precommit checks passed" >&2
fi

exit 0
