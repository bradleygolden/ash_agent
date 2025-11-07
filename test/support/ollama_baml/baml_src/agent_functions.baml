class AgentReply {
  content string
  confidence float
}

function AgentEcho(message: string) -> AgentReply {
  client OllamaClient
  prompt #"
    Respond with a short acknowledgement whose content begins with integration:
    followed by the provided message, and set confidence to 0.99.
    Message: {{ message }}
    {{ ctx.output_format }}
  "#
}
