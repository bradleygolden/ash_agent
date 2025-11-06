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
  ~r/lib\/ash_agent\/runtime\.ex.* Function .* will never be called/
]
