defmodule AshAgent.Test.OllamaClient do
  @moduledoc false
  @baml_src Path.expand("ollama_baml/baml_src", __DIR__)

  alias __MODULE__, as: Client
  alias __MODULE__.AgentReply
  alias __MODULE__.ToolCall
  alias __MODULE__.ToolCallResponse

  def __baml_src_path__, do: @baml_src

  def message_from(%{message: message}) when is_binary(message), do: message
  def message_from(%{"message" => message}) when is_binary(message), do: message
  def message_from(message) when is_binary(message), do: message
  def message_from(_), do: ""

  defmodule AgentReply do
    @moduledoc false
    use Ash.TypedStruct

    typed_struct do
      field :content, :string
      field :confidence, :float
    end
  end

  defmodule ToolCall do
    @moduledoc false
    use Ash.TypedStruct

    typed_struct do
      field :tool_name, :atom
      field :tool_arguments, :map, default: %{}
    end
  end

  defmodule ToolCallResponse do
    @moduledoc false
    use Ash.TypedStruct

    typed_struct do
      field :content, :string
      field :confidence, :float
    end
  end

  defmodule AgentEcho do
    @moduledoc false
    def call(args, _opts \\ []) do
      {:ok, %AgentReply{content: reply_content(args), confidence: 0.99}}
    end

    def stream(args, callback) when is_function(callback) do
      stream(args, callback, %{})
    end

    def stream(args, callback, _opts) when is_function(callback) do
      message = Client.message_from(args)

      pid =
        spawn(fn ->
          message
          |> String.split(" ", trim: true)
          |> Enum.each(fn chunk ->
            callback.({:partial, %AgentReply{content: "integration: #{chunk}", confidence: 0.5}})
          end)

          callback.({:done, %AgentReply{content: reply_content(args), confidence: 0.99}})
        end)

      {:ok, pid}
    end

    defp reply_content(args) do
      "integration: #{Client.message_from(args)}"
    end
  end

  defmodule AgentToolEcho do
    @moduledoc false
    @dialyzer :no_match
    def call(args, _opts \\ []) do
      {:ok, build_response(args)}
    end

    def stream(args, callback) when is_function(callback) do
      stream(args, callback, %{})
    end

    def stream(args, callback, _opts) when is_function(callback) do
      pid =
        spawn(fn ->
          callback.({:done, build_response(args)})
        end)

      {:ok, pid}
    end

    defp build_response(args) do
      message = Client.message_from(args)

      cond do
        tool_result = parse_tool_result(message) ->
          %ToolCallResponse{
            content: format_tool_result_content(tool_result),
            confidence: 0.99
          }

        add_arguments = extract_add_arguments(message) ->
          %ToolCall{tool_name: :add_numbers, tool_arguments: add_arguments}

        requests_original_message?(message) ->
          %ToolCall{tool_name: :get_message, tool_arguments: %{}}

        true ->
          %ToolCallResponse{content: "integration: #{message}", confidence: 0.99}
      end
    end

    defp extract_add_arguments(message) when is_binary(message) do
      numbers =
        Regex.scan(~r/-?\d+/, message)
        |> Enum.map(&hd/1)
        |> Enum.map(&String.to_integer/1)

      if length(numbers) >= 2 do
        %{a: Enum.at(numbers, 0), b: Enum.at(numbers, 1)}
      end
    end

    defp extract_add_arguments(_message), do: nil

    defp requests_original_message?(message) do
      String.contains?(String.downcase(message), "original message")
    end

    defp parse_tool_result(message) when is_map(message), do: message

    defp parse_tool_result(message) when is_binary(message) do
      case Jason.decode(message) do
        {:ok, map} when is_map(map) -> map
        _ -> nil
      end
    rescue
      _ -> nil
    end

    defp parse_tool_result(_), do: nil

    defp format_tool_result_content(result) do
      cond do
        value = Map.get(result, "result") || Map.get(result, :result) ->
          "integration: #{value}"

        message = Map.get(result, "message") || Map.get(result, :message) ->
          "integration: #{message}"

        true ->
          "integration"
      end
    end
  end
end
