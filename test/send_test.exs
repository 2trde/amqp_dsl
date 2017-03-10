defmodule SendTest do
  use AmqpDsl

  messaging do
    queue "test_send" do
    end

    out :sample_send, to_queue: "test_send"
  end
end

defmodule Test.SendTest do
  use ExUnit.Case
  doctest AmqpDsl

  test "test receive msg from queue" do
    {:ok, conn} = AMQP.Connection.open
    {:ok, chan} = AMQP.Channel.open(conn)
    AMQP.Queue.delete(chan, "test_receive")

    {:ok, _pid} = SendTest.start_link()

    test_pid = self

    AMQP.Queue.subscribe(chan, "test_send", fn(payload, _meta) ->
      send test_pid, {:message_received, payload}
    end)

    #SendTest.send_queue("test_send", %{msg: "Hello"})
    SendTest.sample_send(%{msg: "Hello"})

    receive do
      {:message_received, msg} ->
        assert Poison.decode!(msg) == %{"msg" => "Hello"}
    after
      500 -> raise "Failed"
    end
  end
end
