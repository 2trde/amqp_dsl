defmodule Test.RedeliverTest do
  use Test.Support.AmqpCase

  describe "redeliver test" do
    defmodule RedeliverTest do
      use AmqpDsl

      messaging do
        queue "test_receive", durable: true do
          on_receive(msg) do
            :global.send(RedeliverTest, {:message_received, msg})
            raise "bang"
          end
        end
      end
    end

    test "message that raises an exception will be redilivered once" do
      {:ok, conn} = AMQP.Connection.open
      {:ok, chan} = AMQP.Channel.open(conn)
      AMQP.Queue.delete(chan, "test_receive")
      :global.register_name(RedeliverTest, self())
      {:ok, _} = ensure_started(RedeliverTest)

      AMQP.Basic.publish chan, "", "test_receive", "{\"msg\": \"Hello, World!\"}"

      assert_receive {:message_received, _msg}, 500
      assert_receive {:message_received, _msg}, 500
    end
  end
end
