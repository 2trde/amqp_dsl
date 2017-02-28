# AmqpDsl

Simple DSL to describe Messageing with RabbitMQ/AMQP

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `amqp_dsl` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [{:amqp_dsl, "~> 0.1.0"}]
end
```

## Use

The DSL will turn a module into a genserver holding an AMQP connection. It allows
to define queues and exchanges and the binding between them.

Example:

```elixir
defmodule MyMessaging
  use AmqpDsl

  messaging do
    connection "amqp://guest:guest@localhost"

    rpc :my_rpc_request, request_queue: "request.queue", response_queue: "response.queue"

    queue "my.updates"
    on_receive(%{"foo" => payload}) do
      IO.puts "received a foo message with the payload #{inspect payload}"
    end
  end
end
```


Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at [https://hexdocs.pm/amqp_dsl](https://hexdocs.pm/amqp_dsl).

