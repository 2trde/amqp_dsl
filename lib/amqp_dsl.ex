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

  defmacro on_error(error, payload, meta, [do: body]) do
    quote do
      @has_error_handler true
      def on_error(error, payload, meta) do
        unquote(error) = error
        unquote(payload) = payload
        unquote(meta) = meta
        unquote(body)
      end
    end
  end

  defmacro exchange(name, type, options \\ []) do
    quote do
      @exchanges [{unquote(name), unquote(type), unquote(options)} | @exchanges]
    end
  end

  defmacro bind(exchange, options) do
    quote do
      @binding_id @binding_count
      @binding_count @binding_id+1

      def exchange_name_for_binding(@binding_id) do
        unquote(exchange)
      end

      @bindings [{@queue_id, @binding_id, unquote(options)} | @bindings]
    end
  end

  @doc """
  define a queue to be listened
  """
  defmacro queue(name, opts \\ [], clauses \\ []) do
    {opts, clauses} = case {opts, clauses} do
      {[do: _], []} -> {[], opts}
      _ -> {opts, clauses}
    end
    quote do
      @binding_count 1
      @queue_id @queue_count
      @queue_count @queue_count+1
      @queue_opts [passive: false, durable: true, exclusive: false, auto_delete: false, no_wait: false]
      @queue_ids [@queue_id | @queue_ids]
      @have_consume false
      #@current_queue_name unquote(name)

      unquote(clauses[:do])

      def queue_name(@queue_id) do
        unquote(name)
      end

      def consume(@queue_id, _channel, _routing_key, payload, tag) do
        IO.puts "dont know how to route #{inspect payload}"
      end

      def queue_init(channel, @queue_id) do
        AMQP.Queue.declare(channel, unquote(name), Keyword.merge(@queue_opts, unquote(opts)))
        #AMQP.Queue.declare(channel, unquote(name), @queue_opts)
        if @have_consume do
          consumer_pid = spawn_link fn ->
            do_start_consumer(channel, fn(payload, %{delivery_tag: tag, routing_key: routing_key} = meta) ->
              payload = Poison.decode!(payload)
              consume(@queue_id, channel, routing_key, payload, tag)
            end)
          end
          AMQP.Basic.consume(channel, unquote(name), consumer_pid)
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
  defmacro on_receive(msg_var, opts \\ [], [do: body]) when is_list(opts) do
    load_schema = if Keyword.has_key?(opts, :validate_json) do
      quote do
        @schema File.read!(unquote(opts[:validate_json])) |> Poison.decode!() |> ExJsonSchema.Schema.resolve()
      end
    end

    routing_key = if Keyword.has_key?(opts, :routing_key) do
      opts[:routing_key]
    else
      quote do
        _
      end
    end


    validate_json = if opts[:validate_json] do
      quote do
        ExJsonSchema.Validator.validate(@schema, message)
        |> case do
          {:error, error} ->
            raise inspect(error)
          :ok ->
            :ok
        end
      end
    end

    quote do
      unquote(load_schema)

      @have_consume true
      def consume(@queue_id, channel, unquote(routing_key), unquote(msg_var) = message, tag) do
        unquote(validate_json)
        unquote(body)
      end
    end
  end

  defmacro out(name, opts) do
    cond do
      opts[:to_queue] ->
        quote do
          def unquote(name)(message) do
            send_queue(unquote(opts[:to_queue]), message)
          end
        end
      opts[:to_exchange] ->
        quote do
          def unquote(name)(message, key \\ unquote(opts[:routing_key]) ) do
            send_exchange(unquote(opts[:to_exchange]), key, message)
          end
        end
      true ->
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
      @exchanges []
      @bindings []
      @has_error_handler false


      unquote(body)

      def queue_init(_, _), do: raise "default impl of queue_init should never be called!"

      def queue_name(nil), do: raise "invalid queue id"
      def exchange_name_for_binding(nil), do: raise "invalid binding id"

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

            @exchanges
            |> Enum.reverse
            |> Enum.map(fn({name, type, options}) ->
              IO.puts "declaring exchange #{name} with type #{inspect type}"
              AMQP.Exchange.declare(chan, name, type, options)
            end)


            # Register the GenServer process as a consumer
            @queue_ids
            |> Enum.reverse
            |> Enum.map(fn(queue_id) ->
              queue_init(chan, queue_id)
            end)

            @bindings
            |> Enum.reverse
            |> Enum.map(fn({queue, binding_id, options }) ->
              AMQP.Queue.bind(chan, queue_name(queue), exchange_name_for_binding(binding_id), options)
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
        GenServer.cast(__MODULE__, {:send_exchange, "", queue, msg})
      end

      def send_exchange(exchange, key, msg) do
        Poison.encode!(msg)
        GenServer.cast(__MODULE__, {:send_exchange, exchange, key, msg})
      end

      def handle_cast({:send_exchange, exchange, key, msg}, channel) do
        msg = Poison.encode!(msg)
        IO.puts "sendint to exhange '#{exchange}' with key '#{key}'"
        AMQP.Basic.publish(channel, exchange, key, msg)
        {:noreply, channel}
      end

      defp do_consume(channel, fun, consumer_tag) do
        receive do
          {:basic_deliver, payload, %{delivery_tag: delivery_tag} = meta} ->
            try do
              fun.(payload, meta)
              AMQP.Basic.ack(channel, delivery_tag)
            rescue
              exception ->
                if @has_error_handler do
                  IO.puts "adding apply for #{inspect __MODULE__}"
                  apply(__MODULE__, :on_error, [exception , payload, meta])
                else
                  IO.puts "error receiving message: #{inspect exception} for payload #{inspect payload}"
                end
                AMQP.Basic.reject(channel, delivery_tag, requeue: false)
            end
            do_consume(channel, fun, consumer_tag)
          {:basic_cancel, %{consumer_tag: ^consumer_tag, no_wait: _}} ->
            exit(:basic_cancel)
          {:basic_cancel_ok, %{consumer_tag: ^consumer_tag}} ->
            exit(:normal)
        end
      end

      defp do_start_consumer(channel, fun) do
        receive do
          {:basic_consume_ok, %{consumer_tag: consumer_tag}} ->
            do_consume(channel, fun, consumer_tag)
        end
      end
    end
  end
end
