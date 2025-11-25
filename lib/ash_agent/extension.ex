defmodule AshAgent.Extension do
  @moduledoc """
  Public API for AshAgent extensions.

  This module provides a stable, documented API for extension packages like
  `ash_agent_tools` to interact with AshAgent's runtime without depending on
  internal implementation details.

  ## Stability Guarantees

  All functions in this module are part of AshAgent's **public extension API**.
  Breaking changes will follow semantic versioning (major version bumps only).

  ## Extension Packages

  The following packages extend AshAgent using this API:
  - `ash_agent_tools` - Tool-calling runtime for multi-turn agent loops
  - `ash_baml` - BAML function integration as a provider
  - `ash_agent_studio` - Phoenix LiveView observability dashboard and agent playground

  ## Usage

  Extension packages should import this module instead of internal modules:

      # ✅ Good - stable public API
      alias AshAgent.Extension

      config = Extension.get_config(module)
      Extension.render_prompt(prompt, args, config)

      # ❌ Bad - internal modules may change
      alias AshAgent.Runtime.PromptRenderer
      PromptRenderer.render(prompt, args, config)

  ## Available Functions

  ### Configuration
  - `get_config/1` - Get complete agent configuration
  - `apply_runtime_overrides/2` - Apply runtime option overrides
  - `validate_provider_capabilities/2` - Validate provider features

  ### Prompt Rendering
  - `render_prompt/3` - Render prompt template with arguments

  ### Schema Building
  - `build_schema/1` - Build LLM schema from config

  ### Response Parsing
  - `parse_response/2` - Parse LLM response to output type

  ### Hooks
  - `build_context/2` - Build hook context from arguments
  - `execute_hook/3` - Execute hooks with context

  ### LLM Calls
  - `generate_object/7` - Generate structured object via provider
  - `stream_object/7` - Stream structured object via provider
  - `stream_to_structs/2` - Convert stream response to parsed objects
  - `response_usage/2` - Extract usage info from response

  ### Telemetry
  - `telemetry_metadata/3` - Build telemetry metadata
  - `execute_telemetry/3` - Execute telemetry event

  ### Error Construction
  - `config_error/2` - Create configuration error
  - `llm_error/2` - Create LLM error
  - `validation_error/2` - Create validation error
  - `budget_error/2` - Create budget error

  ### Token Limits
  - `check_token_limit/6` - Check token budget limits

  ### Provider Registry
  - `resolve_provider/1` - Resolve provider identifier to module
  """

  alias AshAgent.{Error, Info, ProviderRegistry, SchemaConverter, Telemetry}
  alias AshAgent.Runtime.{Hooks, LLMClient, PromptRenderer}

  # Configuration Functions

  @doc """
  Get the complete agent configuration for a resource.

  This is the primary function extensions should use to retrieve agent config.
  It delegates to `AshAgent.Info.agent_config/1` which is the stable public API.

  ## Returns

  A map with the following keys:
  - `:client` - The client specification
  - `:client_opts` - Additional client options
  - `:provider` - The provider module or preset
  - `:prompt` - The prompt template
  - `:output_type` - The output schema/type
  - `:hooks` - List of hooks configured for the agent
  - `:input_args` - List of input argument definitions
  - `:token_budget` - Token budget limit (if configured)
  - `:budget_strategy` - Budget enforcement strategy
  - `:context_module` - The context module from application config

  ## Examples

      iex> AshAgent.Extension.get_config(MyAgent)
      %{client: "anthropic:claude-3-5-sonnet", ...}
  """
  @spec get_config(module()) :: {:ok, map()} | {:error, term()}
  def get_config(module) do
    config = Info.agent_config(module)
    {:ok, config}
  rescue
    e ->
      {:error,
       Error.config_error("Failed to load agent configuration", %{
         module: module,
         exception: e
       })}
  end

  @doc """
  Apply runtime option overrides to agent configuration.

  Merges runtime options into the base configuration, handling:
  - Provider overrides (resets client_opts if provider changes)
  - Client value and options
  - Profile selection

  ## Options

  - `:provider` - Override the provider
  - `:client` - Override the client (can be `{value, opts}` tuple)
  - `:client_opts` - Merge additional client options
  - `:profile` - Set the profile

  ## Examples

      iex> {:ok, config} = AshAgent.Extension.get_config(MyAgent)
      iex> AshAgent.Extension.apply_runtime_overrides(config, provider: :mock)
      {:ok, %{config | provider: :mock, client_opts: []}}
  """
  @spec apply_runtime_overrides(map(), keyword() | map()) :: {:ok, map()}
  def apply_runtime_overrides(config, runtime_opts) do
    opts =
      cond do
        is_map(runtime_opts) -> Map.to_list(runtime_opts)
        is_list(runtime_opts) -> runtime_opts
        true -> []
      end

    provider = Keyword.get(opts, :provider, config.provider)
    provider_changed? = provider != config.provider

    {client_value, client_override_opts} =
      case Keyword.fetch(opts, :client) do
        {:ok, {value, override_opts}} -> {value, override_opts}
        {:ok, value} -> {value, []}
        :error -> {config.client, []}
      end

    client_opts =
      if(provider_changed?, do: [], else: normalize_client_opts(config.client_opts))
      |> Keyword.merge(normalize_client_opts(client_override_opts))
      |> Keyword.merge(normalize_client_opts(Keyword.get(opts, :client_opts, [])))

    profile = Keyword.get(opts, :profile, config.profile)

    {:ok,
     %{
       config
       | client: client_value,
         client_opts: client_opts,
         provider: provider,
         profile: profile
     }}
  end

  @doc """
  Validate that a provider supports required capabilities.

  Checks the provider's feature list against required features for the
  operation type (`:call` or `:stream`).

  ## Examples

      iex> config = %{provider: :req_llm, tools: []}
      iex> AshAgent.Extension.validate_provider_capabilities(config, :call)
      :ok

      iex> config = %{provider: :mock, tools: [...]}
      iex> AshAgent.Extension.validate_provider_capabilities(config, :call)
      {:error, %AshAgent.Error{...}}
  """
  @spec validate_provider_capabilities(map(), :call | :stream) :: :ok | {:error, term()}
  def validate_provider_capabilities(config, type) do
    features = ProviderRegistry.features(config.provider)

    cond do
      Map.get(config, :tools, []) != [] and :tool_calling not in features ->
        {:error,
         Error.validation_error(
           "Provider #{inspect(config.provider)} does not support tool calling",
           %{provider: config.provider}
         )}

      type == :stream and :streaming not in features ->
        {:error,
         Error.validation_error(
           "Provider #{inspect(config.provider)} does not support streaming",
           %{provider: config.provider}
         )}

      type == :call and :sync_call not in features ->
        {:error,
         Error.validation_error(
           "Provider #{inspect(config.provider)} does not support synchronous calls",
           %{provider: config.provider}
         )}

      true ->
        :ok
    end
  end

  # Prompt Rendering Functions

  @doc """
  Render a prompt template with the given arguments and configuration.

  Delegates to `AshAgent.Runtime.PromptRenderer.render/3`.

  ## Examples

      iex> config = %{output_type: MyType}
      iex> AshAgent.Extension.render_prompt("Hello {{ name }}", %{name: "World"}, config)
      {:ok, "Hello World"}
  """
  @spec render_prompt(binary() | Solid.Template.t(), map(), map()) ::
          {:ok, String.t()} | {:error, term()}
  def render_prompt(template, args, config) do
    PromptRenderer.render(template, args, config)
  end

  # Schema Building Functions

  @doc """
  Build an LLM schema from agent configuration.

  Converts the output type to a schema format required by the provider.

  ## Examples

      iex> config = %{output_type: MyTypedStruct, provider: :req_llm}
      iex> AshAgent.Extension.build_schema(config)
      {:ok, [...schema...]}
  """
  @spec build_schema(map()) :: {:ok, list() | nil} | {:error, term()}
  def build_schema(%{provider: provider} = config) do
    if schema_required?(provider) do
      case config.output_type do
        nil ->
          {:error, Error.schema_error("No output type defined for agent")}

        :string ->
          {:ok, nil}

        type_module ->
          schema = SchemaConverter.to_req_llm_schema(type_module)
          {:ok, schema}
      end
    else
      {:ok, nil}
    end
  rescue
    e ->
      {:error,
       Error.schema_error("Failed to build schema", %{
         output_type: config.output_type,
         exception: e
       })}
  end

  # Response Parsing Functions

  @doc """
  Parse an LLM response into the configured output type.

  Delegates to `AshAgent.Runtime.LLMClient.parse_response/2`.

  ## Examples

      iex> AshAgent.Extension.parse_response(MyType, response)
      {:ok, %MyType{...}}
  """
  @spec parse_response(module() | atom(), term()) :: {:ok, struct()} | {:error, term()}
  def parse_response(output_type, response) do
    LLMClient.parse_response(output_type, response)
  end

  @doc """
  Extract usage information from an LLM response.

  Delegates to `AshAgent.Runtime.LLMClient.response_usage/2`.

  ## Examples

      iex> AshAgent.Extension.response_usage(:req_llm, response)
      %{input_tokens: 100, output_tokens: 50, total_tokens: 150}
  """
  @spec response_usage(atom() | module(), term()) :: map() | nil
  def response_usage(provider, response) do
    LLMClient.response_usage(provider, response)
  end

  # Hook Functions

  @doc """
  Build a hook context from module and arguments.

  Delegates to `AshAgent.Runtime.Hooks.build_context/2`.

  ## Examples

      iex> AshAgent.Extension.build_context(MyAgent, question: "What is Elixir?")
      %AshAgent.Context{input: %{question: "What is Elixir?"}, ...}
  """
  @spec build_context(module(), keyword() | map()) :: map()
  def build_context(module, args) do
    Hooks.build_context(module, args)
  end

  @doc """
  Execute hooks with the given context.

  Delegates to `AshAgent.Runtime.Hooks.execute/3`.

  ## Examples

      iex> hooks = [MyHooks]
      iex> context = %AshAgent.Context{...}
      iex> AshAgent.Extension.execute_hook(hooks, :before_call, context)
      {:ok, %AshAgent.Context{...}}
  """
  @spec execute_hook(list() | nil, atom(), term()) :: {:ok, term()} | {:error, term()}
  def execute_hook(hooks, hook_name, context) do
    Hooks.execute(hooks, hook_name, context)
  end

  @doc """
  Add prompt to hook context.

  Delegates to `AshAgent.Runtime.Hooks.with_prompt/2`.
  """
  @spec with_prompt(map(), String.t()) :: map()
  def with_prompt(context, prompt) do
    Hooks.with_prompt(context, prompt)
  end

  @doc """
  Add response to hook context.

  Delegates to `AshAgent.Runtime.Hooks.with_response/2`.
  """
  @spec with_response(map(), term()) :: map()
  def with_response(context, response) do
    Hooks.with_response(context, response)
  end

  @doc """
  Add error to hook context.

  Delegates to `AshAgent.Runtime.Hooks.with_error/2`.
  """
  @spec with_error(map(), term()) :: map()
  def with_error(context, error) do
    Hooks.with_error(context, error)
  end

  # LLM Call Functions

  @doc """
  Generate a structured object via the configured provider.

  Delegates to `AshAgent.Runtime.LLMClient.generate_object/7`.

  ## Examples

      iex> AshAgent.Extension.generate_object(
      ...>   MyAgent,
      ...>   "anthropic:claude-3-5-sonnet",
      ...>   prompt,
      ...>   schema,
      ...>   [],
      ...>   context,
      ...>   provider_override: :req_llm
      ...> )
      {:ok, response}
  """
  @spec generate_object(module(), term(), term(), term(), keyword(), term(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def generate_object(resource, client, prompt, schema, opts, context, options) do
    LLMClient.generate_object(resource, client, prompt, schema, opts, context, options)
  end

  @doc """
  Stream a structured object via the configured provider.

  Delegates to `AshAgent.Runtime.LLMClient.stream_object/7`.

  ## Examples

      iex> AshAgent.Extension.stream_object(
      ...>   MyAgent,
      ...>   "anthropic:claude-3-5-sonnet",
      ...>   prompt,
      ...>   schema,
      ...>   [],
      ...>   context,
      ...>   provider_override: :req_llm
      ...> )
      {:ok, stream}
  """
  @spec stream_object(module(), term(), term(), term(), keyword(), term(), keyword()) ::
          {:ok, Enumerable.t()} | {:error, term()}
  def stream_object(resource, client, prompt, schema, opts, context, options) do
    LLMClient.stream_object(resource, client, prompt, schema, opts, context, options)
  end

  @doc """
  Convert a stream response to a stream of parsed objects.

  Delegates to `AshAgent.Runtime.LLMClient.stream_to_structs/2`.

  ## Examples

      iex> {:ok, stream_response} = AshAgent.Extension.stream_object(...)
      iex> AshAgent.Extension.stream_to_structs(stream_response, MyType)
      #Stream<...>
  """
  @spec stream_to_structs(Enumerable.t(), module() | atom()) :: Enumerable.t()
  def stream_to_structs(stream_response, output_module) do
    LLMClient.stream_to_structs(stream_response, output_module)
  end

  # Telemetry Functions

  @doc """
  Build telemetry metadata for an agent operation.

  ## Examples

      iex> config = %{client: "...", provider: :req_llm, output_type: MyType}
      iex> AshAgent.Extension.telemetry_metadata(config, MyAgent, :call)
      %{agent: MyAgent, client: "...", provider: :req_llm, type: :call, output_type: MyType}
  """
  @spec telemetry_metadata(map(), module(), atom()) :: map()
  def telemetry_metadata(config, module, type) do
    %{
      agent: module,
      client: config.client,
      provider: config.provider,
      type: type,
      output_type: Map.get(config, :output_type),
      profile: Map.get(config, :profile)
    }
  end

  @doc """
  Execute a telemetry event.

  Wraps `:telemetry.execute/3` with AshAgent namespace prepended.

  ## Examples

      iex> AshAgent.Extension.execute_telemetry([:llm, :request], %{}, %{agent: MyAgent})
      :ok
  """
  @spec execute_telemetry(list(), map(), map()) :: :ok
  def execute_telemetry(event, measurements, metadata) do
    :telemetry.execute([:ash_agent | event], measurements, metadata)
  end

  @doc """
  Execute a telemetry span.

  Delegates to `AshAgent.Telemetry.span/3`.

  ## Examples

      iex> AshAgent.Extension.telemetry_span(:call, %{agent: MyAgent}, fn ->
      ...>   # Do work
      ...>   {result, metadata}
      ...> end)
      result
  """
  @spec telemetry_span(atom(), map(), function()) :: term()
  def telemetry_span(event_name, metadata, fun) do
    Telemetry.span(event_name, metadata, fun)
  end

  # Error Construction Functions

  @doc """
  Create a configuration error.

  ## Examples

      iex> AshAgent.Extension.config_error("Invalid config", %{key: :value})
      %AshAgent.Error{type: :config_error, message: "Invalid config", details: %{key: :value}}
  """
  @spec config_error(String.t(), map()) :: Error.t()
  def config_error(message, details \\ %{}) do
    Error.config_error(message, details)
  end

  @doc """
  Create an LLM error.

  ## Examples

      iex> AshAgent.Extension.llm_error("LLM call failed", %{reason: :timeout})
      %AshAgent.Error{type: :llm_error, message: "LLM call failed", details: %{reason: :timeout}}
  """
  @spec llm_error(String.t(), map()) :: Error.t()
  def llm_error(message, details \\ %{}) do
    Error.llm_error(message, details)
  end

  @doc """
  Create a validation error.

  ## Examples

      iex> AshAgent.Extension.validation_error("Invalid input", %{field: :name})
      %AshAgent.Error{type: :validation_error, message: "Invalid input", details: %{field: :name}}
  """
  @spec validation_error(String.t(), map()) :: Error.t()
  def validation_error(message, details \\ %{}) do
    Error.validation_error(message, details)
  end

  @doc """
  Create a budget error.

  ## Examples

      iex> AshAgent.Extension.budget_error("Budget exceeded", %{limit: 1000})
      %AshAgent.Error{type: :budget_error, message: "Budget exceeded", details: %{limit: 1000}}
  """
  @spec budget_error(String.t(), map()) :: Error.t()
  def budget_error(message, details \\ %{}) do
    Error.budget_error(message, details)
  end

  # Token Limit Functions

  @doc """
  Check token budget limits.

  Delegates to `AshAgent.TokenLimits.check_limit/6`.

  Returns:
  - `:ok` - within limits
  - `{:warn, limit, threshold}` - approaching limit
  - `{:error, :budget_exceeded}` - exceeded limit

  ## Examples

      iex> AshAgent.Extension.check_token_limit(500, "anthropic:claude-3-5-sonnet", nil, nil, 1000, :halt)
      :ok
  """
  @spec check_token_limit(
          non_neg_integer(),
          term(),
          map() | nil,
          float() | nil,
          non_neg_integer() | nil,
          atom() | nil
        ) :: :ok | {:warn, non_neg_integer(), float()} | {:error, :budget_exceeded}
  def check_token_limit(
        cumulative_tokens,
        client,
        limits \\ nil,
        threshold \\ nil,
        budget \\ nil,
        strategy \\ :warn
      ) do
    alias AshAgent.TokenLimits

    TokenLimits.check_limit(
      cumulative_tokens,
      client,
      limits,
      threshold,
      budget,
      strategy
    )
  end

  # Provider Registry Functions

  @doc """
  Resolve a provider identifier to its module.

  Delegates to `AshAgent.ProviderRegistry.resolve/1`.

  ## Examples

      iex> AshAgent.Extension.resolve_provider(:req_llm)
      {:ok, AshAgent.Providers.ReqLLM}

      iex> AshAgent.Extension.resolve_provider(:unknown)
      {:error, "Provider :unknown not found"}
  """
  @spec resolve_provider(atom() | module()) :: {:ok, module()} | {:error, String.t()}
  def resolve_provider(provider) do
    ProviderRegistry.resolve(provider)
  end

  # Private Helpers

  defp normalize_client_opts(nil), do: []
  defp normalize_client_opts(opts) when is_list(opts), do: opts
  defp normalize_client_opts(%{} = map), do: Map.to_list(map)
  defp normalize_client_opts(other), do: List.wrap(other)

  defp schema_required?(provider) do
    case ProviderRegistry.resolve(provider) do
      {:ok, provider_module} ->
        if function_exported?(provider_module, :introspect, 0) do
          features = provider_module.introspect() |> Map.get(:features, [])
          :schema_optional not in features
        else
          true
        end

      {:error, _} ->
        true
    end
  end
end
