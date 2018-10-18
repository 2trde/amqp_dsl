defmodule SendTest do
  use AmqpDsl

  def queue_name(), do: "test_send"
  def exchange_name(), do: "test_exchange"

  messaging do
    exchange "test_exchange", :topic

    out :sample_send, to_exchange: "test_exchange", routing_key: "bla"
  end
end

defmodule Test.ExchangeTest do
  use ExUnit.Case
  doctest AmqpDsl

  test "test receive msg from queue" do
    {:ok, conn} = AMQP.Connection.open
    {:ok, chan} = AMQP.Channel.open(conn)
    AMQP.Queue.delete(chan, "test_send")
    AMQP.Exchange.delete(chan, "test_exchange")

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
  end
end
