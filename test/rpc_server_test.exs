defmodule RpcServerTest do
  use AmqpDsl

  messaging do
    queue "test_rpc_request"
    queue "test_rpc_response"

    rpc_in(msg, "test_rpc_request", "test_rpc_response") do
      %{response: "received #{msg["msg"]}"}
    end
  end
end

defmodule Test.RpcServerTest do
  use ExUnit.Case
  doctest AmqpDsl

  test "test receive msg from queue" do
    {:ok, conn} = AMQP.Connection.open
    {:ok, chan} = AMQP.Channel.open(conn)
    AMQP.Queue.delete(chan, "test_rpc_request")
    AMQP.Queue.delete(chan, "test_rpc_response")

    {:ok, pid} = RpcServerTest.start_link()

    me = self()

    AMQP.Basic.publish chan, "", "test_rpc_request", "{\"msg\": \"Hello, World!\"}"
    AMQP.Queue.subscribe(chan, "test_rpc_response", fn(payload, _) ->
      send me, {:message_received, Poison.decode!(payload)}
    end)

    receive do
      {:message_received, msg} ->
        assert msg == %{"response" => "received Hello, World!"}
    after
      20000 -> raise "Failed"
    end
  end
end

