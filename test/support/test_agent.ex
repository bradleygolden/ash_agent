defmodule AshAgent.Test.TestAgent do
  @moduledoc """
  A simple test agent for testing AshAgent functionality.
  """
  use Ash.Resource, domain: nil, extensions: [AshAgent.Resource]

  alias AshAgent.Test.Reply

  agent do
    client("anthropic:claude-3-5-sonnet", temperature: 0.7, max_tokens: 100)

    output(Reply)

    prompt("You are a test assistant. Respond to: {{ message }}")
  end

  code_interface do
    define :call
    define :stream
  end
end
