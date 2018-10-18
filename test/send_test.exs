defmodule SendTest do
  use AmqpDsl

  messaging do
    out :sample_send, to_queue: "test_send"
  end
end

defmodule Test.SendTest do
  use ExUnit.Case
  doctest AmqpDsl

  test "test receive msg from queue" do
    {:ok, conn} = AMQP.Connection.open
    {:ok, chan} = AMQP.Channel.open(conn)
    AMQP.Queue.delete(chan, "test_send")

    {:ok, pid} = SendTest.start_link()

    test_pid = self

    AMQP.Queue.declare(chan, "test_send")
    AMQP.Queue.subscribe(chan, "test_send", fn(payload, _meta) ->
      send test_pid, {:message_received, payload}
    end)

    SendTest.sample_send(%{msg: "Hello"})

    receive do
      {:message_received, msg} ->
        assert Poison.decode!(msg) == %{"msg" => "Hello"}
    after
      500 -> raise "Failed"
    end
    Process.exit(pid, :normal)
    Process.exit(conn.pid, :normal)
  end

  test "send to unknown exchange, then sending should still work (not kill anything)" do
    {:ok, conn} = AMQP.Connection.open
    {:ok, chan} = AMQP.Channel.open(conn)
    AMQP.Queue.delete(chan, "test_receive")
    AMQP.Queue.delete(chan, "test_send")

    {:ok, pid} = SendTest.start_link()

    # sending a message to an unknown exchange
    SendTest.send_exchange("unknown_exchange", "some_routing_key", "hey, I am going to be lost")

    test_pid = self

    AMQP.Queue.declare(chan, "test_send")
    AMQP.Queue.subscribe(chan, "test_send", fn(payload, _meta) ->
      send test_pid, {:message_received, payload}
    end)

    SendTest.sample_send(%{msg: "Hello"})

    receive do
      {:message_received, msg} ->
        assert Poison.decode!(msg) == %{"msg" => "Hello"}
    after
      500 -> raise "Failed"
    end
    Process.exit(pid, :normal)
    Process.exit(conn.pid, :normal)
  end
end
