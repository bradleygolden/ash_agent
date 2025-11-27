defmodule AshAgent.Providers.BamlProviderCallbackOrderTest do
  use ExUnit.Case, async: true

  alias AshAgent.Providers.Baml

  defmodule StreamClient.Stream do
    def stream(args, callback) do
      callback.({:partial, %{message: {:partial, args[:message]}}})
      callback.({:done, %{message: {:done, args[:message]}}})
      self()
    end

    def stream(args, callback, opts) do
      send(self(), {:opts_seen, opts})
      stream(args, callback)
    end
  end

  test "streams with BamlElixir.Client signature: stream(args, callback, opts)" do
    context = %{input: %{message: "hi"}}
    opts = [client_module: StreamClient, function: :Stream]

    assert {:ok, stream} =
             Baml.stream(:client, nil, nil, opts, context, nil, nil)

    [partial, final] = Enum.to_list(stream)
    assert %{message: {:partial, "hi"}} = partial
    assert %AshBaml.Response{data: %{message: {:done, "hi"}}} = final
    assert_received {:opts_seen, %{collectors: [%BamlElixir.Collector{}]}}
  end
end
