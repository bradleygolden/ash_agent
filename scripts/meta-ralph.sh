#!/usr/bin/env bash

set -euo pipefail

PROMPT_ARG="${1:-PROMPT.md}"

if [[ -f "$PROMPT_ARG" ]]; then
  PROMPT_CONTENT=$(cat "$PROMPT_ARG")
  echo "📖 Meta-Ralph is reading from file: $PROMPT_ARG"
else
  PROMPT_CONTENT="$PROMPT_ARG"
  echo "📝 Meta-Ralph is using prompt string"
fi

echo ""
echo "🎪 Meta-Ralph is starting the infinite loop!"
echo "💡 Press Ctrl+C to stop Ralph from learnding"
echo ""

ITERATION=1

while true; do
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "🔄 ITERATION $ITERATION - I'm learnding!"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  DATE=$(date +"%Y-%m-%d-%H-%M-%S")
  SESSION_DIR=".springfield/meta-ralph-$DATE-iteration-$ITERATION"

  echo "📁 Session: $SESSION_DIR"
  echo ""

  mkdir -p "$SESSION_DIR"

  echo "$PROMPT_CONTENT" > "$SESSION_DIR/task.txt"

  echo '{"status":"init","phase":"lisa","iteration":0,"kickbacks":{}}' > "$SESSION_DIR/state.json"

  echo "🎬 Springfield is working on iteration $ITERATION..."
  echo ""

  echo "$PROMPT_CONTENT" | claude code -m "Springfield, please work on this task. Session directory: $SESSION_DIR" || {
    echo "⚠️  Springfield workflow failed on iteration $ITERATION"
    echo "📝 Check $SESSION_DIR for details"
    sleep 5
  }

  echo ""
  echo "✅ Iteration $ITERATION complete!"
  echo ""
  echo "⏸️  Pausing for 3 seconds before next iteration..."
  sleep 3

  ITERATION=$((ITERATION + 1))
done
