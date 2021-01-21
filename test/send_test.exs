defmodule Test.SendTest do
  use Test.Support.AmqpCase

  describe "Send test" do
    defmodule SendTest do
      use AmqpDsl

      messaging do
        out :sample_send, to_queue: "test_send"
      end
    end

    test "receive msg from queue" do
      {:ok, conn} = AMQP.Connection.open
      {:ok, chan} = AMQP.Channel.open(conn)
      AMQP.Queue.delete(chan, "test_send")

      {:ok, _} = ensure_started(SendTest)

      test_pid = self()
      AMQP.Queue.declare(chan, "test_send")
      AMQP.Queue.subscribe(chan, "test_send", fn(payload, _meta) -> send test_pid, {:message_received, payload} end)

      SendTest.sample_send(%{msg: "Hello"})

      assert_receive {:message_received, msg}
      assert Poison.decode!(msg) == %{"msg" => "Hello"}
    end

    test "send to unknown exchange, then sending should still work (not kill anything)" do
      {:ok, conn} = AMQP.Connection.open
      {:ok, chan} = AMQP.Channel.open(conn)
      AMQP.Queue.delete(chan, "test_send")

      {:ok, _} = ensure_started(SendTest)

      # sending a message to an unknown exchange
      SendTest.send_exchange("unknown_exchange", "some_routing_key", "hey, I am going to be lost")

      test_pid = self()
      AMQP.Queue.declare(chan, "test_send")
      AMQP.Queue.subscribe(chan, "test_send", fn(payload, _meta) -> send test_pid, {:message_received, payload} end)

      SendTest.sample_send(%{msg: "Hello"})

      assert_receive {:message_received, msg}
      assert Poison.decode!(msg) == %{"msg" => "Hello"}
    end
  end
end
