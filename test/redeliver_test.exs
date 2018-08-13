defmodule RedeliverTest do
  use AmqpDsl

  messaging do
    queue "test_receive", durable: true do
      on_receive(msg, routing_key: "test_receive") do
        :global.send(RedeliverTest, {:message_received, msg})
        raise "bang"
      end
    end
  end
end

defmodule Test.RedeliverTest do
  use ExUnit.Case
  doctest AmqpDsl

  test "test that a message that raises an exception will be redilivered once" do
    {:ok, conn} = AMQP.Connection.open
    {:ok, chan} = AMQP.Channel.open(conn)
    AMQP.Queue.delete(chan, "test_receive")

    {:ok, _pid} = RedeliverTest.start_link()

    :global.register_name(RedeliverTest, self())
    AMQP.Basic.publish chan, "", "test_receive", "{\"msg\": \"Hello, World!\"}"
    assert_receive {:message_received, _msg}, 500
    assert_receive {:message_received, _msg}, 500
  end
end
