defmodule AshAgent.Domain.Transformers.GenerateAgents do
  @moduledoc """
  Generates agent resource modules from template fragments.

  For each template registered in the `agents` block, this transformer creates
  a thin wrapper resource that:
  1. Uses the template as a Spark fragment (inherits output, inputs, prompt)
  2. Adds the client/provider configuration from the domain
  3. Includes any consumer-specified extensions
  """
  use Spark.Dsl.Transformer

  alias Spark.Dsl.Transformer

  @impl true
  def after?(AshAgent.Transformers.AddDomainInterfaces), do: false
  def after?(_), do: false

  @impl true
  def before?(AshAgent.Transformers.AddDomainInterfaces), do: true
  def before?(_), do: false

  @impl true
  def transform(dsl_state) do
    domain = Transformer.get_persisted(dsl_state, :module)
    agent_configs = Transformer.get_entities(dsl_state, [:agents])

    dsl_state =
      Enum.reduce(agent_configs, dsl_state, fn config, dsl_state ->
        module_name = agent_module_name(domain, config)
        generate_agent_module(domain, module_name, config)
        add_resource_to_domain(dsl_state, module_name)
      end)

    {:ok, dsl_state}
  end

  defp generate_agent_module(domain, module_name, config) do
    template = config.template
    {client, client_opts} = config.client
    provider = config.provider || :req_llm

    extensions = resolve_extensions(config)
    extensions_list = [AshAgent.Resource | extensions]

    code = """
    defmodule #{inspect(module_name)} do
      @ash_agent_client #{inspect({client, client_opts})}
      @ash_agent_provider #{inspect(provider)}

      use Ash.Resource,
        domain: #{inspect(domain)},
        extensions: #{inspect(extensions_list)},
        fragments: [#{inspect(template)}],
        validate_domain_inclusion?: false

      resource do
        require_primary_key?(false)
      end
    end
    """

    Code.compile_string(code)
  end

  defp resolve_extensions(config) do
    (config.extensions || [])
    |> Enum.map(&normalize_extension/1)
    |> Enum.filter(&extension_available?/1)
  end

  defp normalize_extension(ext) when is_atom(ext), do: ext
  defp normalize_extension({ext, _opts}) when is_atom(ext), do: ext

  defp extension_available?(ext) do
    Code.ensure_loaded?(ext)
  end

  defp add_resource_to_domain(dsl_state, module_name) do
    resource_reference = %Ash.Domain.Dsl.ResourceReference{
      resource: module_name,
      definitions: []
    }

    Transformer.add_entity(dsl_state, [:resources], resource_reference)
  end

  defp agent_module_name(domain, %{as: as}) when not is_nil(as) do
    capitalized = as |> Atom.to_string() |> Macro.camelize() |> String.to_atom()
    Module.concat(domain, capitalized)
  end

  defp agent_module_name(domain, %{template: template}) do
    last_segment = template |> Module.split() |> List.last() |> String.to_atom()
    Module.concat(domain, last_segment)
  end
end
