defmodule AshAgent.Test.TestAgents do
  @moduledoc """
  Collection of reusable test agent definitions for various testing scenarios.

  This module provides common agent configurations that can be reused across
  different test files to ensure consistency and reduce duplication.
  """

  defmodule SimpleOutput do
    @moduledoc false
    use Ash.TypedStruct

    typed_struct do
      field :message, :string, allow_nil?: false
    end
  end

  defmodule ComplexOutput do
    @moduledoc false
    use Ash.TypedStruct

    typed_struct do
      field :title, :string, allow_nil?: false
      field :description, :string
      field :score, :float
      field :tags, {:array, :string}
    end
  end

  defmodule MinimalAgent do
    @moduledoc """
    Minimal agent with just required configuration.
    Useful for testing basic functionality.
    """
    use Ash.Resource,
      domain: AshAgent.Test.TestAgents.TestDomain,
      extensions: [AshAgent.Resource]

    agent do
      client "anthropic:claude-3-5-sonnet"
      output SimpleOutput
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

    import AshAgent.Sigils

    agent do
      client "anthropic:claude-3-5-sonnet"
      output SimpleOutput
      prompt ~p"Process: {{ input }}"

      input do
        argument :input, :string
      end
    end
  end

  defmodule AgentWithComplexOutput do
    @moduledoc """
    Agent with complex nested output structure.
    Useful for testing schema conversion with multiple field types.
    """
    use Ash.Resource,
      domain: AshAgent.Test.TestAgents.TestDomain,
      extensions: [AshAgent.Resource]

    agent do
      client "anthropic:claude-3-5-sonnet"
      output ComplexOutput
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

    agent do
      client("anthropic:claude-3-5-sonnet", temperature: 0.5, max_tokens: 200)
      output SimpleOutput
      prompt "Test with options"
    end
  end

  defmodule AgentWithMultipleArgs do
    @moduledoc """
    Agent that accepts multiple arguments.
    Useful for testing complex prompt templating.
    """
    use Ash.Resource,
      domain: AshAgent.Test.TestAgents.TestDomain,
      extensions: [AshAgent.Resource]

    import AshAgent.Sigils

    agent do
      client "anthropic:claude-3-5-sonnet"
      output ComplexOutput
      prompt ~p"Task: {{ task }} with priority {{ priority }}"

      input do
        argument :task, :string
        argument :priority, :string
      end
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
  Returns a stub response for SimpleOutput.
  """
  def simple_response(message) do
    %{"message" => message}
  end

  @doc """
  Returns a stub response for ComplexOutput.
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
