client<llm> OpenAIClient {
  provider openai
  options {
    model "gpt-4o-mini"
    api_key env.OPENAI_API_KEY
  }
}

class MetadataTestResponse {
  response string
}

function MetadataTest(message: string) -> MetadataTestResponse {
  client OpenAIClient
  prompt #"
    Reply with a JSON object containing a single "response" field with your reply.
    Message: {{ message }}
    {{ ctx.output_format }}
  "#
}
