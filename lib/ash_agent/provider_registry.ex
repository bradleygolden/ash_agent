defmodule AshAgent.ProviderRegistry do
  @moduledoc """
  Central registry for resolving provider identifiers to modules.

  Providers can be configured globally via application config:

      config :ash_agent,
        providers: [
          custom: MyApp.CustomProvider
        ]

  Built-in providers:
  - `:req_llm` → `AshAgent.Providers.ReqLLM`
  - `:mock` → `AshAgent.Providers.Mock`
  - `:baml` → `AshAgent.Providers.Baml` (requires ash_baml as optional dependency)

  ## Dynamic Registration

  External providers can register themselves at runtime using `register/2`:

      # In external provider package application.ex
      def start(_type, _args) do
        AshAgent.ProviderRegistry.register(:custom, MyApp.CustomProvider)
        # ...
      end

  This enables loose coupling where provider packages can extend AshAgent
  without creating circular dependencies.
  """

  use GenServer
  alias AshAgent.Error

  @type provider_key :: atom() | module()

  @default_providers %{
    req_llm: AshAgent.Providers.ReqLLM,
    mock: AshAgent.Providers.Mock,
    baml: AshAgent.Providers.Baml
  }

  @default_provider_keys Map.keys(@default_providers)

  @default_provider_features %{
    req_llm: [
      :sync_call,
      :streaming,
      :structured_output,
      :tool_calling,
      :auto_retry
    ],
    mock: [
      :sync_call,
      :streaming,
      :structured_output,
      :configurable_responses,
      :tool_calling
    ],
    baml: [
      :sync_call,
      :streaming,
      :structured_output,
      :tool_calling,
      :prompt_optional,
      :schema_optional
    ]
  }

  ## GenServer API

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  @doc """
  Registers a provider dynamically at runtime.

  This allows external provider packages to register themselves when they're loaded,
  enabling loose coupling between core and provider packages.

  ## Example

      # In external provider application startup
      AshAgent.ProviderRegistry.register(:custom, MyApp.CustomProvider)
  """
  @spec register(atom(), module()) :: :ok
  def register(key, module) when is_atom(key) and is_atom(module) do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, {:register, key, module})
    else
      # Registry not started yet, skip registration
      # This can happen during compilation
      :ok
    end
  end

  @doc """
  Resolves a provider identifier or module to an implementing module.

  Configured providers take precedence over dynamically registered providers,
  which take precedence over built-ins.
  """
  @spec resolve(provider_key()) :: {:ok, module()} | {:error, Error.t()}

  def resolve(module) when is_atom(module) and module not in @default_provider_keys do
    if Code.ensure_loaded?(module) do
      {:ok, module}
    else
      {:error,
       Error.config_error("Provider module #{inspect(module)} could not be resolved", %{
         provider: module
       })}
    end
  end

  def resolve(key) when is_atom(key) do
    providers =
      Application.get_env(:ash_agent, :providers, [])
      |> Map.new()

    # Priority: configured > dynamic > built-in
    dynamic_providers = get_dynamic_providers()

    case Map.get(providers, key) || Map.get(dynamic_providers, key) ||
           Map.get(@default_providers, key) do
      nil ->
        {:error,
         Error.config_error("Unknown provider #{inspect(key)}", %{
           provider: key,
           available_providers: available_providers(providers, dynamic_providers)
         })}

      module ->
        {:ok, module}
    end
  end

  def resolve(other) do
    {:error,
     Error.config_error("Invalid provider specification #{inspect(other)}", %{
       provider: other
     })}
  end

  @doc """
  Returns the declared feature list for a provider, or an empty list if unavailable.
  """
  @spec features(provider_key()) :: [atom()]
  def features(provider) do
    case resolve(provider) do
      {:ok, module} -> module_features(module, provider)
      {:error, _} -> []
    end
  end

  defp available_providers(providers, dynamic_providers) do
    providers
    |> Map.merge(dynamic_providers)
    |> Map.merge(@default_providers)
    |> Map.keys()
  end

  defp get_dynamic_providers do
    if Process.whereis(__MODULE__) do
      GenServer.call(__MODULE__, :get_providers)
    else
      %{}
    end
  end

  ## GenServer Callbacks

  @impl true
  def init(_) do
    {:ok, %{}}
  end

  @impl true
  def handle_call({:register, key, module}, _from, state) do
    {:reply, :ok, Map.put(state, key, module)}
  end

  @impl true
  def handle_call(:get_providers, _from, state) do
    {:reply, state, state}
  end

  defp module_features(module, provider_key) do
    cond do
      function_exported?(module, :introspect, 0) ->
        module.introspect()
        |> Map.get(:features, [])

      default_features(provider_key) ->
        default_features(provider_key)

      key = provider_key_for_module(module) ->
        default_features(key)

      true ->
        []
    end
  rescue
    _ ->
      default_features(provider_key) ||
        []
  end

  defp default_features(provider_key) do
    @default_provider_features[provider_key]
  end

  defp provider_key_for_module(module) do
    Enum.find_value(@default_providers, fn {key, mod} ->
      if mod == module, do: key
    end)
  end
end
