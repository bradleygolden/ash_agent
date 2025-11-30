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

class ToolCall {
  tool_name string
  tool_arguments map<string>
}

class ToolCallResponse {
  content string
  confidence float
}

union AgentToolResponse {
  ToolCall
  ToolCallResponse
}

function AgentToolEcho(message: string) -> AgentToolResponse {
  client OllamaClient
  prompt #"
    You are a helpful assistant with access to tools.
    When asked to perform calculations, use the add_numbers tool.
    When asked about the original message, use the get_message tool.

    Available tools:
    - add_numbers: Add two numbers together. Takes parameters: a (integer), b (integer)
    - get_message: Get the original message. Takes no parameters.

    If you need to call a tool, return a ToolCall with tool_name and tool_arguments.
    Otherwise, return a ToolCallResponse with content and confidence set to 0.99.

    Message: {{ message }}
    {{ ctx.output_format }}
  "#
}

class SearchAction {
  intent "search"
  query string
}

class DoneAction {
  intent "done"
  answer string
}

union AgentLoopResponse {
  SearchAction
  DoneAction
}

function AgentLoop(message: string, iteration: int) -> AgentLoopResponse {
  client OllamaClient
  prompt #"
    Help the user. Current iteration: {{ iteration }}.
    Task: {{ message }}

    Respond with JSON matching one of the output types:
    - If iteration < 3: {"intent": "search", "query": "<search query>"}
    - If iteration >= 3: {"intent": "done", "answer": "<final answer>"}

    {{ ctx.output_format }}
  "#
}
