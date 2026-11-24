defmodule Hologram.Auth.SpawnMarkHandleTest do
  # Not async: these tests take away the trace session every process marks itself in.
  use Hologram.Test.BasicCase, async: false

  import Hologram.Auth.SpawnMark

  @session_key {Hologram.Auth.SpawnMark, :trace_session}

  setup do
    session = :persistent_term.get(@session_key)

    on_exit(fn -> :persistent_term.put(@session_key, session) end)
  end

  describe "forget/0" do
    test "leaves sessions with nothing to mark, rather than refused by a dead tracer" do
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

    test "does nothing when there's no handle" do
      forget()

      assert forget() == :ok
    end
  end
end
