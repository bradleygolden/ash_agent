defmodule AshAgent.Test.TestAgents do
  @moduledoc """
  Collection of reusable test agent definitions for various testing scenarios.

  This module provides common agent configurations that can be reused across
  different test files to ensure consistency and reduce duplication.
  """

  defmodule MinimalAgent do
    @moduledoc """
    Minimal agent with just required configuration.
    Useful for testing basic functionality.
    """
    use Ash.Resource,
      domain: AshAgent.Test.TestAgents.TestDomain,
      extensions: [AshAgent.Resource]

    resource do
      require_primary_key? false
    end

    agent do
      client "anthropic:claude-3-5-sonnet"
      output_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
      prompt "Simple test"
    end
  end

  defmodule AgentWithArguments do
    @moduledoc """
    Agent that accepts input arguments.
    Useful for testing prompt variable interpolation.
    """
    use Ash.Resource,
      domain: AshAgent.Test.TestAgents.TestDomain,
      extensions: [AshAgent.Resource]

    resource do
      require_primary_key? false
    end

    import AshAgent.Sigils

    agent do
      client "anthropic:claude-3-5-sonnet"
      output_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
      prompt ~p"Process: {{ input }}"
    end
  end

  defmodule AgentWithComplexOutput do
    @moduledoc """
    Agent with complex nested output structure.
    Useful for testing schema validation with multiple field types.
    """
    use Ash.Resource,
      domain: AshAgent.Test.TestAgents.TestDomain,
      extensions: [AshAgent.Resource]

    resource do
      require_primary_key? false
    end

    agent do
      client "anthropic:claude-3-5-sonnet"

      output_schema(
        Zoi.object(
          %{
            title: Zoi.string(),
            description: Zoi.string() |> Zoi.optional(),
            score: Zoi.float() |> Zoi.optional(),
            tags: Zoi.list(Zoi.string()) |> Zoi.optional()
          },
          coerce: true
        )
      )

      prompt "Generate complex output"
    end
  end

  defmodule AgentWithClientOpts do
    @moduledoc """
    Agent with custom client options.
    Useful for testing client configuration.
    """
    use Ash.Resource,
      domain: AshAgent.Test.TestAgents.TestDomain,
      extensions: [AshAgent.Resource]

    resource do
      require_primary_key? false
    end

    agent do
      client("anthropic:claude-3-5-sonnet", temperature: 0.5, max_tokens: 200)
      output_schema(Zoi.object(%{message: Zoi.string()}, coerce: true))
      prompt "Test with options"
    end
  end

  defmodule AgentWithMultipleArgs do
    @moduledoc """
    Agent that accepts multiple arguments via template variables.
    Useful for testing complex prompt templating.
    """
    use Ash.Resource,
      domain: AshAgent.Test.TestAgents.TestDomain,
      extensions: [AshAgent.Resource]

    resource do
      require_primary_key? false
    end

    import AshAgent.Sigils

    agent do
      client "anthropic:claude-3-5-sonnet"

      output_schema(
        Zoi.object(
          %{
            title: Zoi.string(),
            description: Zoi.string() |> Zoi.optional(),
            score: Zoi.float() |> Zoi.optional(),
            tags: Zoi.list(Zoi.string()) |> Zoi.optional()
          },
          coerce: true
        )
      )

      prompt ~p"Task: {{ task }} with priority {{ priority }}"
    end
  end

  defmodule TestDomain do
    @moduledoc false
    use Ash.Domain, validate_config_inclusion?: false

    resources do
      resource MinimalAgent
      resource AgentWithArguments
      resource AgentWithComplexOutput
      resource AgentWithClientOpts
      resource AgentWithMultipleArgs
    end
  end

  @doc """
  Returns a stub response for simple output schema.
  """
  def simple_response(message) do
    %{"message" => message}
  end

  @doc """
  Returns a stub response for complex output schema.
  """
  def complex_response(opts \\ []) do
    %{
      "title" => Keyword.get(opts, :title, "Test Title"),
      "description" => Keyword.get(opts, :description, "Test description"),
      "score" => Keyword.get(opts, :score, 0.85),
      "tags" => Keyword.get(opts, :tags, ["test", "example"])
    }
  end
end
