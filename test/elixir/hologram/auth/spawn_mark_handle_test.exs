defmodule Hologram.Auth.SpawnMarkHandleTest do
  # Not async: these tests take away the trace session every process marks itself in.
  use Hologram.Test.BasicCase, async: false

  import Hologram.Auth.SpawnMark

  @session_key {Hologram.Auth.SpawnMark, :trace_session}

  setup do
    session = :persistent_term.get(@session_key)

    on_exit(fn -> :persistent_term.put(@session_key, session) end)

    [session: session]
  end

  # Takes the name from the run's tracer until the test ends, the way a stopped app leaves it.
  defp without_running_tracer do
    tracer = Process.whereis(Hologram.Auth.SpawnMark)
    Process.unregister(Hologram.Auth.SpawnMark)

    on_exit(fn -> Process.register(tracer, Hologram.Auth.SpawnMark) end)
  end

  describe "forget/0" do
    test "leaves sessions with nothing to mark, rather than refused by a dead tracer" do
      without_running_tracer()

      tracer = spawn(fn -> Process.sleep(:infinity) end)
      :persistent_term.put(@session_key, :trace.session_create(__MODULE__, tracer, []))

      monitor = Process.monitor(tracer)
      Process.exit(tracer, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^tracer, :killed}, 5_000

      assert_raise RuntimeError, fn -> put(true) end

      assert forget() == :ok
      assert put(true) == :ok
      refute marked?()
    end

    test "keeps a running tracer's handle", %{session: session} do
      assert forget() == :ok
      assert :persistent_term.get(@session_key) == session
    end

    test "does nothing when there's no handle" do
      without_running_tracer()
      forget()

      assert forget() == :ok
    end
  end
end
