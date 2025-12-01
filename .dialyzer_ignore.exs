[
  # BAML provider false positives from incomplete type specs
  ~r/lib\/ash_agent\/providers\/baml\.ex.* The pattern .* can never match/,
  # Test support files with Zoi schema definitions trigger guard_fail warnings
  {"test/support/test_agents.ex", :guard_fail},
  # Test stub dialyzer warnings
  ~r/test\/support\/ollama_client_stub\.ex/
]
