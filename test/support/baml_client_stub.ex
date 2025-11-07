defmodule AshAgent.Test.BamlClient do
  @moduledoc false

  defmodule Reply do
    @moduledoc false
    use Ash.TypedStruct

    typed_struct do
      field :content, :string
    end
  end

  defmodule ChatAgent do
    @moduledoc false

    def call(args, _opts \\ []) do
      message = extract_arg(args, :message)
      {:ok, %Reply{content: "BAML reply: #{message}"}}
    end

    def stream(args, callback) do
      message = extract_arg(args, :message)
      pid = spawn(fn -> send_chunks(message, callback) end)
      {:ok, pid}
    end

    defp send_chunks(message, callback) do
      Enum.each(String.split(message, " "), fn chunk ->
        callback.({:partial, %Reply{content: chunk}})
      end)

      callback.({:done, %Reply{content: message}})
    end

    defp extract_arg(map, key) when is_map(map) do
      Map.get(map, key) || Map.get(map, Atom.to_string(key))
    end
  end
end
