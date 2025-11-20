defmodule AshAgent.Providers.BamlProviderCallbackOrderTest do
  use ExUnit.Case, async: true

  defmodule StreamClient.Stream do
    def stream(args, callback) do
      callback.({:partial, %{message: {:partial, args[:message]}}})
      callback.({:done, %{message: {:done, args[:message]}}})
      self()
    end

    def stream(args, opts, callback) do
      send(self(), {:opts_seen, opts})
      stream(args, callback)
    end
  end

  test "streams when callback is second arg and opts are third" do
    context = %{input: %{message: "hi"}}
    opts = [client_module: StreamClient, function: :Stream]

    assert {:ok, stream} =
             AshAgent.Providers.Baml.stream(:client, nil, nil, opts, context, nil, nil)

    assert [%{message: {:partial, "hi"}}, %{message: {:done, "hi"}}] == Enum.to_list(stream)
    assert_received {:opts_seen, %{}}
  end
end
