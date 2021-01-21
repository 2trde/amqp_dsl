defmodule Test.Support.AmqpCase do
  use ExUnit.CaseTemplate

  using do
    quote do
      import Test.Support.AmqpCase
    end
  end

  def ensure_started(module) do
    start_tracking(module)
    {:ok, pid} = module.start_link([])
    ensure_handle_continue(pid, module)
    {:ok, pid}
  end

  defp start_tracking(module) do
    :erlang.trace(:new, true, [:call, :return_to])
    :erlang.trace_pattern({module, :handle_continue, 2}, true, [:local])
    :ok
  end

  defp ensure_handle_continue(pid, module) do
    assert_receive {:trace, ^pid, :call, {^module, :handle_continue, [:connect, nil]}}
    assert_receive {:trace, ^pid, :return_to, {:gen_server, :try_dispatch, 4}}
  end
end
