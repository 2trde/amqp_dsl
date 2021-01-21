defmodule Test.ExchangeTest do
  use Test.Support.AmqpCase

  describe "exchange test" do
    defmodule ExchangeTest do
      use AmqpDsl

      messaging do
        exchange "test_exchange", :topic

        out :sample_send, to_exchange: "test_exchange", routing_key: "bla"
      end
    end

    test "receive msg from queue" do
      {:ok, conn} = AMQP.Connection.open
      {:ok, chan} = AMQP.Channel.open(conn)
      AMQP.Queue.delete(chan, "test_send")
      AMQP.Exchange.delete(chan, "test_exchange")

      ensure_started(ExchangeTest)

      test_pid = self()

      AMQP.Queue.declare(chan, "test_send")
      AMQP.Queue.subscribe(chan, "test_send", fn(payload, _meta) -> send test_pid, {:message_received, payload} end)
      AMQP.Queue.bind(chan, "test_send", "test_exchange", routing_key: "bla")

      ExchangeTest.sample_send(%{msg: "Hello"})

      assert_receive {:message_received, msg}, 1000
      assert Poison.decode!(msg) == %{"msg" => "Hello"}
    end
  end
end
