defmodule Test.OnReceiveTest do
  use Test.Support.AmqpCase

  describe "on receive test" do
    defmodule OnReceiveTest do
      use AmqpDsl

      messaging do
        on_error(error, _, _) do
          :global.send(OnReceiveTest, {:error_received, error})
        end

        queue "test_receive", durable: false do
          on_receive(%{"name" => "Hans"}) do
            :global.send(OnReceiveTest, {:message_received, "Hans"})
          end
          on_receive(%{"name" => "Wurst"}) do
            :global.send(OnReceiveTest, {:message_received, "Wurst"})
          end
        end
      end
    end

    test "receive msg from queue" do
      {:ok, conn} = AMQP.Connection.open
      {:ok, chan} = AMQP.Channel.open(conn)
      AMQP.Queue.delete(chan, "test_receive")
      :global.register_name(OnReceiveTest, self())

      {:ok, _} = ensure_started(OnReceiveTest)

      AMQP.Basic.publish chan, "", "test_receive", "{\"name\": \"Hans\", \"age\": 15}"
      AMQP.Basic.publish chan, "", "test_receive", "{\"name\": \"Wurst\", \"age\": 15}"
      assert_receive {:message_received, "Hans"}
      assert_receive {:message_received, "Wurst"}
    end
  end
end
