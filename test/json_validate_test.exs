defmodule ReceiveJsonTest do
  use AmqpDsl

  messaging do
    on_error(error, _, _) do
      :global.send(ReceiveJsonTest, {:error_received, error.message})
    end

    queue "test_receive", durable: false do
      on_receive(%{"name" => _, "age" => _} = msg, validate_json: "test/schema.json") do
        IO.puts "***********************"
        :global.send(ReceiveJsonTest, {:message_received, msg})
      end
    end
  end
end

defmodule Test.JsonValidateTest do
  use ExUnit.Case
  doctest AmqpDsl

  test "test receive msg from queue" do
    {:ok, conn} = AMQP.Connection.open
    {:ok, chan} = AMQP.Channel.open(conn)
    AMQP.Queue.delete(chan, "test_receive")

    {:ok, _pid} = ReceiveJsonTest.start_link()
    :global.register_name(ReceiveJsonTest, self())

    AMQP.Basic.publish chan, "", "test_receive", "{\"name\": \"Hans\", \"age\": 15}"
    assert_receive {:message_received, msg}
    assert msg == %{"name" => "Hans", "age" => 15}
    AMQP.Basic.publish chan, "", "test_receive", "{\"name\": \"Hans\", \"age\": \"15\"}"
    refute_receive {:message_received, _}
    assert_receive {:error_received, "[{\"Type mismatch. Expected Integer but got String.\", \"#/age\"}]"}
  end
end
