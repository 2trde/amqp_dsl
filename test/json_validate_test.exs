defmodule Test.JsonValidateTest do
  use Test.Support.AmqpCase

  describe "validate json" do
    defmodule ReceiveJsonTest do
      use AmqpDsl

      messaging do
        on_error(error, _, _) do
          :global.send(ReceiveJsonTest, {:error_received, error.message})
        end

        queue "test_receive", durable: false do
          on_receive(%{"name" => _, "age" => _} = msg, validate_json: "test/support/fixtures/schema.json") do
            :global.send(ReceiveJsonTest, {:message_received, msg})
          end
        end
      end
    end

    test "test receive msg from queue" do
      {:ok, conn} = AMQP.Connection.open
      {:ok, chan} = AMQP.Channel.open(conn)
      AMQP.Queue.delete(chan, "test_receive")
      :global.register_name(ReceiveJsonTest, self())

      {:ok, _} = ensure_started(ReceiveJsonTest)

      AMQP.Basic.publish chan, "", "test_receive", "{\"name\": \"Hans\", \"age\": 15}"
      assert_receive {:message_received, msg}
      assert msg == %{"name" => "Hans", "age" => 15}
      AMQP.Basic.publish chan, "", "test_receive", "{\"name\": \"Hans\", \"age\": \"15\"}"
      refute_receive {:message_received, _}
      assert_receive {:error_received, "[{\"Type mismatch. Expected Integer but got String.\", \"#/age\"}]"}
    end
  end

end
