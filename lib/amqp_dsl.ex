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
      @queue_id @queue_count
      @queue_count @queue_count+1
      @queue_opts [passive: false, durable: true, exclusive: false, auto_delete: false, no_wait: false]
      @queue_ids [@queue_id | @queue_ids]
      @have_consume false

      unquote(clauses[:do])

      def consume(@queue_id, channel, payload, tag) do
        IO.puts "dont know how to route #{inspect payload}"
      end

      def queue_init(channel, @queue_id) do
        AMQP.Queue.declare(channel, unquote(name), @queue_opts)
        if @have_consume do
          AMQP.Queue.subscribe(channel, unquote(name), fn(payload, %{delivery_tag: tag} = _meta) ->
            payload = Poison.decode!(payload)
            consume(@queue_id, channel, payload, tag)
          end)
        end
      end
      @queue_id nil
    end
  end

  def inspect_code(ast) do
    IO.puts Macro.to_string(ast)
    ast
  end

  @doc """
  define a on receive block. The first parameter can pattern match on the json message.
  So you can define multiple blocks
  """
  defmacro on_receive(msg_var, [do: body]) do
    quote do
      @have_consume true
      def consume(@queue_id, channel, unquote(msg_var) = message, tag) do
        unquote(msg_var) = message
        unquote(body)
      end
    end
  end

  defmacro rpc_in(msg_var, request_queue_name, response_queue_name, [do: body]) do
    quote do
      @queue_id @queue_count
      @queue_count @queue_count+1
      @queue_opts [passive: false, durable: true, exclusive: false, auto_delete: false, no_wait: false]
      @queue_ids [@queue_id | @queue_ids]

      def consume(@queue_id, channel, message, correlation_id, tag) do
        unquote(msg_var) = message
        result = unquote(body)
        result = Poison.encode!(result)
        AMQP.Basic.publish(channel, "", unquote(response_queue_name), result,
                           correlation_id: correlation_id)
      end

      def queue_init(channel, @queue_id) do
        AMQP.Queue.subscribe(channel, unquote(request_queue_name), fn(payload, %{delivery_tag: tag, correlation_id: correlation_id} = _meta) ->
          payload = Poison.decode!(payload)
          consume(@queue_id, channel, payload, correlation_id, tag)
        end)
      end
      @queue_id nil
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
  defmacro rpc_out(name, request_queue, response_queue) do
    quote do
      def unquote(name)(msg) do
        GenServer.call(__MODULE__, {unquote(name), msg}, 3000)
      end

      def handle_call({unquote(name), msg}, _from, channel) do
        response =
          Task.async(fn() ->
            # queue for the response
            AMQP.Basic.consume(channel, unquote(response_queue), nil, no_ack: true)

            msg = msg |> Poison.encode!()

            correlation_id =
              :erlang.unique_integer() |> :erlang.integer_to_binary()
              |> Base.encode64()

            AMQP.Basic.publish(channel, "", unquote(request_queue), msg,
                               reply_to: unquote(response_queue),
                               correlation_id: correlation_id)

            receive do
              {:basic_deliver, payload, %{correlation_id: ^correlation_id}} ->
                payload
                |> Poison.decode!()
            end
          end)
          |> Task.await

        {:reply, response, channel}
      end
    end
  end

  defmacro out(name, opts) do
    if opts[:to_queue] do
      quote do
        def unquote(name)(message) do
          send_queue(unquote(opts[:to_queue]), message)
        end
      end
    else
      raise "out expects to_queue parameter"
    end
  end


  @doc """
  main macro to define messaging for a module. The module will become an GenServer and can be
  put into a supervisor like a genserver
  """
  defmacro messaging([do: body]) do
    quote do
      @queue_ids []
      @queue_count 0
      @defined_connection false
      unquote(body)

      unless @defined_connection do
        def connection(), do: "amqp://guest:guest@localhost"
      end

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
            @queue_ids
            |> Enum.reverse
            |> Enum.map(fn(queue_id) ->
              queue_init(chan, queue_id)
            end)
            {:ok, chan}
          {:error, _} ->
            # Reconnection loop
            :timer.sleep(5000)
            rabbitmq_connect()
        end
      end

      def init(_opts) do
        {:ok, chan} = rabbitmq_connect()
      end

      def handle_info({:DOWN, _, :process, _pid, _reason}, _) do
        {:ok, chan} = rabbitmq_connect()
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

      def send_queue(queue, msg) do
        Poison.encode!(msg)
        GenServer.cast(__MODULE__, {:send_queue, queue, msg})
      end

      def handle_cast({:send_queue, queue, msg}, channel) do
        msg = Poison.encode!(msg)
        AMQP.Basic.publish(channel, "", queue, msg)
        {:noreply, channel}
      end
    end
  end
end
