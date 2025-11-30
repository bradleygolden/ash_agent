class AgentLoopResponse {
  intent string
  query string?
  answer string?
}

function AgentLoop(message: string, iteration: int) -> AgentLoopResponse {
  client OllamaClient
  prompt #"
    Help the user. Current iteration: {{ iteration }}.
    Task: {{ message }}

    IMPORTANT: Follow these rules exactly:
    - If iteration < 3: intent MUST be "search", query MUST be a non-empty string, answer should be null
    - If iteration >= 3: intent MUST be "done", answer MUST be a non-empty string, query should be null

    Never set intent to "done" unless iteration is 3 or greater.
    Never return answer as null when intent is "done".

    {{ ctx.output_format }}
  "#
}
