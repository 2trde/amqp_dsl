defmodule OnReceiveTest do
  use AmqpDsl

  messaging do
    on_error(error, payload, _) do
      :global.send(OnReceiveTest, {:error_received, error})
    end

    queue "test_receive", durable: false do
      on_receive(%{"name" => "Hans"} = msg) do
        :global.send(OnReceiveTest, {:message_received, "Hans"})
      end
      on_receive(%{"name" => "Wurst"} = msg) do
        :global.send(OnReceiveTest, {:message_received, "Wurst"})
      end
    end
  end
end

defmodule Test.OnReceiveTest do
  use ExUnit.Case
  doctest AmqpDsl

  test "test receive msg from queue" do
    {:ok, conn} = AMQP.Connection.open
    {:ok, chan} = AMQP.Channel.open(conn)
    AMQP.Queue.delete(chan, "test_receive")

    {:ok, pid} = OnReceiveTest.start_link()
    :global.register_name(OnReceiveTest, self)

    AMQP.Basic.publish chan, "", "test_receive", "{\"name\": \"Hans\", \"age\": 15}"
    AMQP.Basic.publish chan, "", "test_receive", "{\"name\": \"Wurst\", \"age\": 15}"
    assert_receive {:message_received, "Hans"}
    assert_receive {:message_received, "Wurst"}
  end
end


