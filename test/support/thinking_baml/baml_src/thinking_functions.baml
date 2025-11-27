class MathAnswer {
  answer int
  explanation string
}

function SolveWithThinking(question: string) -> MathAnswer {
  client ClaudeThinking
  prompt #"
    Solve this math problem: {{ question }}
    {{ ctx.output_format }}
  "#
}

function AnswerWithThinking(question: string) -> string {
  client ClaudeThinking
  prompt #"
    Answer this question briefly: {{ question }}
  "#
}
