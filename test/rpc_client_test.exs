defmodule RpcClientTestServer do
  use AmqpDsl

  messaging do
    queue "test_rpc_request"
    queue "test_rpc_response"

    rpc_in(msg, "test_rpc_request", "test_rpc_response") do
      #%{response: "received #{msg["msg"]}"}
      %{response: "received #{msg["msg"]}"}
    end
  end
end

defmodule RpcClientTest do
  use AmqpDsl

  messaging do
    queue "test_rpc_request"
    queue "test_rpc_response"

    rpc_out :bid, "test_rpc_request", "test_rpc_response"
  end
end

defmodule Test.RpcClientTest do
  use ExUnit.Case
  doctest AmqpDsl

  test "test receive msg from queue" do
    {:ok, conn} = AMQP.Connection.open
    {:ok, chan} = AMQP.Channel.open(conn)
    AMQP.Queue.delete(chan, "test_rpc_request")
    AMQP.Queue.delete(chan, "test_rpc_response")

    {:ok, _pid} = RpcClientTest.start_link()
    {:ok, _pid} = RpcClientTestServer.start_link()

    result = RpcClientTest.bid(%{msg: "hello"})
    assert result == %{"response" => "received hello"}
  end
end

