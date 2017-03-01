defmodule AmqpDsl do
  defmacro __using__(_) do
    quote do
      require AmqpDsl
      import AmqpDsl

      use GenServer
      use AMQP
    end
  end

  @doc """
  define connection of amqp server

  ## Example

  messaging do
    connection "amqp://user:pw@my_amqp_host"
  end
  """
  defmacro connection(val) do
    quote do
      @defined_connection true
      def connection() do
        unquote(val)
      end
    end
  end

  @doc """
  define a queue to be listened
  """
  defmacro queue(name, clauses \\ []) do
    quote do
      def queue_name(@queue_count), do: unquote(name)
      unquote(clauses[:do])
      @queue_count @queue_count+1
    end
  end

  @doc """
  define a on receive block. The first parameter can pattern match on the json message.
  So you can define multiple blocks
  """
  defmacro on_receive(msg_var, [do: body]) do
    quote do
      def consume(channel, unquote(msg_var) = message, tag) do
        unquote(msg_var) = message
        unquote(body)
        AMQP.Basic.ack channel, tag
      end
    end
  end

  @doc """
  define an rpc call (outgoing). It allows to send to an queue and receive on a temporary
  queue the immediate response

  ## Example

  messaging do
    rpc :bid, request_queue: "my_requests", response_queue: "my_responses"
  end

  This will define a bid method in the module that can be called with a message
  and it will return the answer message
  """
  defmacro rpc(name, opts) do
    quote do
      def unquote(name)(msg) do
        GenServer.call(__MODULE__, {unquote(name), msg}, 3000)
      end

      def handle_call({unquote(name), msg}, _from, channel) do
        # queue for the response
        resp_qname = unquote(opts[:response_queue])
        req_qname = unquote(opts[:request_queue])
        {:ok, %{queue: _}} = AMQP.Queue.declare(channel, resp_qname, exclusive: true)
        AMQP.Basic.consume(channel, resp_qname, nil, no_ack: true)

        msg = msg |> Poison.encode!()

        correlation_id =
          :erlang.unique_integer() |> :erlang.integer_to_binary()
          |> Base.encode64()

        AMQP.Basic.publish(channel, "", req_qname, msg,
                           reply_to: resp_qname,
                           correlation_id: correlation_id)

        response =
          receive do
            {:basic_deliver, payload, %{correlation_id: ^correlation_id}} ->
              payload
              |> Poison.decode!()
          end

        {:reply, response, channel}
      end
    end
  end


  @doc """
  main macro to define messaging for a module. The module will become an GenServer and can be
  put into a supervisor like a genserver
  """
  defmacro messaging([do: body]) do
    quote do
      @queue_count 0
      unquote(body)

      #unless @defined_connection do
      #  def connection(), do: "amqp://guest:guest@localhost"
      #end

      def start_link do
        GenServer.start_link(__MODULE__, [], name: __MODULE__)
      end

      def rabbitmq_connect() do
        IO.puts "AMQP connection to #{connection()}"
        AMQP.Connection.open(connection())
        |> case do
          {:ok, conn} ->
            Process.monitor(conn.pid)
            {:ok, chan} = AMQP.Channel.open(conn)

            # Limit unacknowledged messages to 10
            AMQP.Basic.qos(chan, prefetch_count: 10)

            # Register the GenServer process as a consumer
            (0..@queue_count-1)
            |> Enum.map(fn(i) -> queue_name(i) end)
            |> Enum.map(fn(name) ->
              {:ok, consumer_tag} = AMQP.Basic.consume(chan, name)
              IO.puts "consumer_tag: #{consumer_tag}"
            end)
            {:ok, chan}
          {:error, _} ->
            # Reconnection loop
            :timer.sleep(5000)
            rabbitmq_connect
        end
      end

      def init(_opts) do
        {:ok, chan} = rabbitmq_connect()
      end

      def handle_info({:DOWN, _, :process, _pid, _reason}, _) do
        {:ok, chan} = rabbitmq_connect
        {:noreply, chan}
      end

      # Confirmation sent by the broker after registering this process as a consumer
      def handle_info({:basic_consume_ok, %{consumer_tag: consumer_tag}}, chan) do
        {:noreply, chan}
      end

      # Sent by the broker when the consumer is unexpectedly cancelled (such as after a queue deletion)
      def handle_info({:basic_cancel, %{consumer_tag: consumer_tag}}, chan) do
        {:stop, :normal, chan}
      end

      # Confirmation sent by the broker to the consumer process after a Basic.cancel
      def handle_info({:basic_cancel_ok, %{consumer_tag: consumer_tag}}, chan) do
        {:noreply, chan}
      end

      def handle_info({:basic_deliver, payload, %{delivery_tag: tag} = meta}, chan) do
        payload = Poison.decode!(payload)
        spawn fn ->
          consume(chan, payload, tag)
        end
        {:noreply, chan}
      end

      def consume(channel, body, tag) do
        IO.puts "dont know how to route #{inspect body}"
      end
    end
  end
end
