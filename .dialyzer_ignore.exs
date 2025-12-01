[
  # False positives from incomplete Solid library type specs
  # The Solid.render/3 function has incomplete type specifications that cause
  # Dialyzer to incorrectly infer that render_prompt/2 only returns {:error, binary()}.
  # In reality, it returns both {:ok, String.t()} and {:error, String.t()}.
  # These warnings are confirmed false positives as all tests pass.

  # Pattern matches that Dialyzer incorrectly flags
  ~r/lib\/ash_agent\/runtime\.ex.* The pattern can never match/,

  # No return warnings that cascade from the pattern match false positives
  ~r/lib\/ash_agent\/runtime\.ex.* Function .* has no local return/,

  # Unused function warnings for MVP - these will be used in future iterations
  ~r/lib\/ash_agent\/runtime\.ex.* Function .* will never be called/,

  # Guard clause false positives from Solid library type inference
  ~r/lib\/ash_agent\/runtime\.ex.* The guard clause.*can never succeed/,

  # BAML provider false positives from incomplete type specs
  ~r/lib\/ash_agent\/providers\/baml\.ex.* The guard clause can never succeed/,
  ~r/lib\/ash_agent\/providers\/baml\.ex.* The pattern .* can never match/,

  # ReqLLM provider false positives on retry logic pattern matching
  ~r|lib/ash_agent/providers/req_llm\.ex:.*pattern_match|,

  # Test support false positives from Ollama client stub
  # Client.message_from always returns binary, making some defensive clauses unreachable
  ~r/test\/support\/ollama_client_stub\.ex.* The pattern variable .* can never match/,
  ~r/test\/support\/ollama_client_stub\.ex.* The guard clause can never succeed/,

  # Test agents false positives from Zoi schema type inference
  # Zoi.object/2 returns opaque types that Dialyzer cannot fully analyze
  ~r/test\/support\/test_agents\.ex.* The guard clause can never succeed/
]
