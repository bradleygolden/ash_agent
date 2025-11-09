defmodule AshAgent.Integration.ReqLLMIntegrationTest do
  use ExUnit.Case, async: false

  @moduletag :integration

  setup_all do
    ReqLLM.put_key(:openai_api_key, "ollama")
    :ok
  end

  setup do
    original_opts = Application.get_env(:ash_agent, :req_llm_options, [])
    Application.put_env(:ash_agent, :req_llm_options, [])

    on_exit(fn ->
      Application.put_env(:ash_agent, :req_llm_options, original_opts)
    end)

    :ok
  end

  defmodule ReqLLMAgent do
    use Ash.Resource,
      domain: AshAgent.TestDomain,
      extensions: [AshAgent.Resource]

    import AshAgent.Sigils

    resource do
      require_primary_key? false
    end

    defmodule Reply do
      use Ash.TypedStruct

      typed_struct do
        field :content, :string, allow_nil?: false
        field :confidence, :float
      end
    end

    agent do
      client("openai:qwen3:1.7b",
        base_url: "http://localhost:11434/v1",
        api_key: "ollama",
        temperature: 0.0
      )

      output(Reply)

      input do
        argument :message, :string, allow_nil?: false
      end

      prompt(~p"""
      Reply with JSON matching ctx.output_format exactly.
      content must start with "req integration:" followed by the message.
      confidence must be 0.99.
      Message: {{ message }}
      {{ ctx.output_format }}
      """)
    end

    code_interface do
      define :call, args: [:message]
    end
  end

  describe "req_llm provider against Ollama" do
    test "code interface reaches local LLM" do
      assert {:ok, %ReqLLMAgent.Reply{} = reply} = ReqLLMAgent.call("ping")

      assert String.starts_with?(reply.content, "req integration")
      assert reply.confidence == 0.99
    end

    test "Ash.run_action uses same pipeline" do
      input =
        ReqLLMAgent
        |> Ash.ActionInput.for_action(:call, %{message: "from action"})

      assert {:ok, %ReqLLMAgent.Reply{} = reply} = Ash.run_action(input)
      assert String.starts_with?(reply.content, "req integration")
      assert reply.confidence == 0.99
    end
  end
end
