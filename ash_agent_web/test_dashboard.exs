#!/usr/bin/env elixir

# Quick test script to generate agent calls for dashboard testing
# Run with: elixir -S mix run ash_agent_web/test_dashboard.exs

# Make sure you have ANTHROPIC_API_KEY set
unless System.get_env("ANTHROPIC_API_KEY") do
  IO.puts("Warning: ANTHROPIC_API_KEY not set. Using mock provider instead.")
end

questions = [
  "What time is it?",
  "Give me a random number between 1 and 50",
  "Calculate 42 times 7",
  "Echo this message: Hello from the dashboard!",
  "What's a random number between 100 and 200?"
]

IO.puts("Starting dashboard test with #{length(questions)} questions...")
IO.puts("Open http://localhost:4001/agents/Elixir.Examples.DemoAgent to watch\n")

for {question, index} <- Enum.with_index(questions, 1) do
  IO.puts("[#{index}/#{length(questions)}] Asking: #{question}")

  try do
    result = Examples.DemoAgent.call!(question: question)
    IO.puts("  ✓ Response: #{String.slice(to_string(result), 0, 100)}")
  rescue
    e ->
      IO.puts("  ✗ Error: #{Exception.message(e)}")
  end

  # Small delay between calls so you can see them in the dashboard
  Process.sleep(1000)
end

IO.puts("\n✓ Dashboard test complete!")
IO.puts("Check the metrics at http://localhost:4001/agents/Elixir.Examples.DemoAgent")
