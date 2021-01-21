defmodule Test.LoopTest do
  use Test.Support.AmqpCase

  describe "loop test" do
    defmodule LoopTest do
      use AmqpDsl
    	use AmqpDsl.Loop

      messaging do
        loop_list ["pa", "pb"] do
          exchange "#{@current}.exchange", :topic
          queue "#{@current}.queue" do
            bind "#{@current}.exchange", routing_key: "bla"

            on_receive(msg) do
              :global.send(LoopTest, {:message_received, msg})
            end
          end
        end
      end
    end

    test "test receive msg from queue" do
      {:ok, conn} = AMQP.Connection.open
      {:ok, chan} = AMQP.Channel.open(conn)
      AMQP.Queue.delete(chan, "test_receive")
      :global.register_name(LoopTest, self())

      {:ok, _} = ensure_started(LoopTest)

      AMQP.Basic.publish chan, "pa.exchange", "bla", "123"
      AMQP.Basic.publish chan, "pb.exchange", "bla", "456"
      assert_receive {:message_received, 123}
      assert_receive {:message_received, 456}
    end
  end
end
