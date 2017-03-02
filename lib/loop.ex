defmodule AmqpDsl.Loop do
  defmacro __using__(_) do
    quote do
      require AmqpDsl.Loop
      import AmqpDsl.Loop
    end
  end

  defmacro loop_list(list, [do: block]) do
    list
    |> Enum.reduce(nil, fn(x, acc) ->
      quote do
        unquote(acc)
        @current unquote(x)
        unquote(block)
      end
    end)
  end
end
