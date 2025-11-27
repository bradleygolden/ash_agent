client<llm> ClaudeThinking {
  provider anthropic
  options {
    model "claude-haiku-4-5-20251001"
    api_key env.ANTHROPIC_API_KEY
    max_tokens 16000
    thinking {
      type "enabled"
      budget_tokens 5000
    }
  }
}
