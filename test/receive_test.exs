defmodule ReceiveTest do
  use AmqpDsl

  messaging do
    queue "test_receive" do
      on_receive(msg) do
        :global.send(ReceiveTest, {:message_received, msg})
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
    AMQP.Basic.publish chan, "", "test_receive", "Hello, World!"
    receive do
      {:message_received, msg} ->
        assert msg == "Hello, World!"
    after
      500 -> raise "Failed"
    end
  end
end
