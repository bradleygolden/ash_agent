defmodule AshAgent.Result do
  @moduledoc """
  Wrapper for agent call responses containing parsed output and rich metadata.

  Provides a unified interface for accessing response data regardless of
  the underlying provider (ReqLLM, BAML, Mock).

  ## Fields

  - `:output` - The parsed output struct (e.g., %MyOutput{})
  - `:thinking` - Thinking/reasoning content from the model (nil if unsupported)
  - `:usage` - Token usage statistics map
  - `:model` - Model identifier used for generation
  - `:finish_reason` - Why generation stopped (:stop, :length, :tool_calls, etc.)
  - `:metadata` - Provider-specific metadata map (extensible)
  - `:raw_response` - Original provider response (for debugging)

  ## Example

      {:ok, result} = AshAgent.Runtime.call(MyAgent, input: "Hello")
      result.output     #=> %MyOutput{message: "Hi there!"}
      result.thinking   #=> "The user greeted me, I should respond warmly..."
      result.usage      #=> %{input_tokens: 10, output_tokens: 5, total_tokens: 15}

      # Access via functions
      AshAgent.Result.thinking(result)  #=> "The user greeted me..."
      AshAgent.Result.unwrap(result)    #=> %MyOutput{message: "Hi there!"}
  """

  defstruct [
    :output,
    :thinking,
    :usage,
    :model,
    :finish_reason,
    metadata: %{},
    raw_response: nil
  ]

  @type usage :: %{
          optional(:input_tokens) => non_neg_integer(),
          optional(:output_tokens) => non_neg_integer(),
          optional(:total_tokens) => non_neg_integer(),
          optional(:reasoning_tokens) => non_neg_integer()
        }

  @type finish_reason :: :stop | :length | :tool_calls | :content_filter | :error | atom()

  @type t :: %__MODULE__{
          output: struct() | term(),
          thinking: String.t() | nil,
          usage: usage() | nil,
          model: String.t() | nil,
          finish_reason: finish_reason() | nil,
          metadata: map(),
          raw_response: term()
        }

  @doc """
  Creates a new Result struct with the given output and options.

  ## Options

  - `:thinking` - Thinking/reasoning content
  - `:usage` - Token usage map
  - `:model` - Model identifier
  - `:finish_reason` - Generation stop reason
  - `:metadata` - Provider-specific metadata
  - `:raw_response` - Original provider response

  ## Examples

      iex> AshAgent.Result.new(%MyOutput{message: "Hello"})
      %AshAgent.Result{output: %MyOutput{message: "Hello"}}

      iex> AshAgent.Result.new(%MyOutput{}, thinking: "Thinking...", usage: %{input_tokens: 10})
      %AshAgent.Result{output: %MyOutput{}, thinking: "Thinking...", usage: %{input_tokens: 10}}
  """
  def new(output, opts \\ []) do
    %__MODULE__{
      output: output,
      thinking: Keyword.get(opts, :thinking),
      usage: Keyword.get(opts, :usage),
      model: Keyword.get(opts, :model),
      finish_reason: Keyword.get(opts, :finish_reason),
      metadata: Keyword.get(opts, :metadata, %{}),
      raw_response: Keyword.get(opts, :raw_response)
    }
  end

  @doc """
  Returns the parsed output struct from the result.

  ## Examples

      iex> result = AshAgent.Result.new(%MyOutput{message: "Hi"})
      iex> AshAgent.Result.output(result)
      %MyOutput{message: "Hi"}
  """
  def output(%__MODULE__{output: output}), do: output

  @doc """
  Returns the thinking/reasoning content, or nil if not available.

  ## Examples

      iex> result = AshAgent.Result.new(%{}, thinking: "Let me think...")
      iex> AshAgent.Result.thinking(result)
      "Let me think..."
  """
  def thinking(%__MODULE__{thinking: thinking}), do: thinking

  @doc """
  Returns the token usage map, or nil if not available.

  ## Examples

      iex> result = AshAgent.Result.new(%{}, usage: %{input_tokens: 10, output_tokens: 5})
      iex> AshAgent.Result.usage(result)
      %{input_tokens: 10, output_tokens: 5}
  """
  def usage(%__MODULE__{usage: usage}), do: usage

  @doc """
  Returns the model identifier, or nil if not available.
  """
  def model(%__MODULE__{model: model}), do: model

  @doc """
  Returns the finish reason, or nil if not available.
  """
  def finish_reason(%__MODULE__{finish_reason: reason}), do: reason

  @doc """
  Returns the metadata map.
  """
  def metadata(%__MODULE__{metadata: metadata}), do: metadata

  @doc """
  Returns the raw provider response for debugging.
  """
  def raw_response(%__MODULE__{raw_response: raw}), do: raw

  @doc """
  Unwraps the result, returning just the output struct.

  Alias for `output/1`. Useful for quick access when metadata is not needed.

  ## Examples

      iex> result = AshAgent.Result.new(%MyOutput{message: "Hi"})
      iex> AshAgent.Result.unwrap(result)
      %MyOutput{message: "Hi"}
  """
  def unwrap(%__MODULE__{output: output}), do: output
end
