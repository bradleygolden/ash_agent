class AgentReply {
  content string
  confidence float
}

class ToolCall {
  tool_name string
  tool_arguments map<string, string>
}

class ToolCallResponse {
  content string
  confidence float
}

class ContentResponse {
  content string
}

function AgentEcho(message: string) -> AgentReply {
  client OllamaClient
  prompt #"
    You are a helpful assistant.
    Respond to the user's message concisely.

    Message: {{ message }}
    {{ ctx.output_format }}
  "#
}

function AgentWithTools(message: string) -> ToolCall | ToolCallResponse {
  client OllamaClient
  prompt #"
    You are a helpful assistant with access to tools.

    When the user asks for the current time, use the get_time tool.
    When the user asks for a random number, use the random_number tool with appropriate min/max values.
    When the user asks you to echo something, use the echo tool.
    When the user asks for calculations, use the calculate tool with operation (:add, :subtract, :multiply, :divide) and numbers.

    Available tools:
    - get_time: Gets the current time in UTC. No parameters needed.
    - random_number: Generates a random number. Parameters: min (integer, optional), max (integer, optional)
    - echo: Echoes back a message. Parameters: message (string, required)
    - calculate: Performs arithmetic. Parameters: operation (string: "add", "subtract", "multiply", "divide"), a (integer), b (integer)
    - submit_answer: Submit the final answer to complete the task. Parameters: answer (string, required), confidence (string: "low", "medium", or "high", optional)

    IMPORTANT: After calling any tool and getting its result, you MUST call submit_answer with the final answer to complete the task.

    If you need to call a tool, return a ToolCall with tool_name and tool_arguments as key-value pairs.
    Otherwise, return a ToolCallResponse with your response content and confidence (0.0 to 1.0).

    Message: {{ message }}
    {{ ctx.output_format }}
  "#
}

function MultiInputAgent(
  topic: string,
  content_type: string,
  audience: string,
  word_count: int,
  include_examples: bool
) -> ContentResponse {
  client OllamaClient
  prompt #"
    Generate a {{ content_type }} about {{ topic }} with the following specifications:
    - Target audience: {{ audience }}
    - Word count: approximately {{ word_count }} words
    - Include examples: {{ include_examples }}

    {{ ctx.output_format }}
  "#
}
