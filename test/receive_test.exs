defmodule ReceiveTest do
  use AmqpDsl

  messaging do
    queue "test_receive" do
      on_receive(msg) do
        :global.send(ReceiveTest, {:message_received, msg})
        raise "bang"
      end
    end
  end
end

defmodule Test.ReceiveTest do
  use ExUnit.Case
  doctest AmqpDsl

  test "test receive msg from queue" do
    {:ok, conn} = AMQP.Connection.open
    {:ok, chan} = AMQP.Channel.open(conn)
    AMQP.Queue.delete(chan, "test_receive")

    {:ok, pid} = ReceiveTest.start_link()

    :global.register_name(ReceiveTest, self)
    AMQP.Basic.publish chan, "", "test_receive", "{\"msg\": \"Hello, World!\"}"
    AMQP.Basic.publish chan, "", "test_receive", "{\"msg\": \"Hello, World!\"}"
    assert_receive {:message_received, msg}, 500
    assert msg == %{"msg" => "Hello, World!"}
    assert_receive {:message_received, msg}, 500
    assert msg == %{"msg" => "Hello, World!"}
  end
end
