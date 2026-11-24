defmodule Hologram.Auth.SpawnMarkTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Auth.SpawnMark

  # Long enough for a loaded CI runner: a passing test never waits it out.
  @receive_timeout 5_000

  # A trace session of the test's own, so nothing here touches the one the app runs on.
  defp start_session do
    tracer = spawn(fn -> Process.sleep(:infinity) end)

    {:trace.session_create(__MODULE__, tracer, []), tracer}
  end

  defp marked_in_spawned_process(session) do
    test_pid = self()
    spawn(fn -> send(test_pid, {:marked, marked?(session)}) end)

    assert_receive {:marked, marked?}, @receive_timeout

    marked?
  end

  describe "marked?/1" do
    test "is false for a process that was never marked" do
      {session, _tracer} = start_session()

      refute marked?(session)
    end

    test "is false with no trace session" do
      refute marked?(nil)
    end
  end

  describe "served_or_ended?/2" do
    # Starts a process that runs the function, tells the test and stays alive.
    defp start_process(fun) do
      test_pid = self()

      pid =
        spawn(fn ->
          fun.()
          send(test_pid, :ready)
          Process.sleep(:infinity)
        end)

      assert_receive :ready, @receive_timeout

      pid
    end

    test "is false for a process that never held the mark" do
      {session, _tracer} = start_session()
      pid = start_process(fn -> :ok end)

      refute served_or_ended?(pid, session)
    end

    test "is true for a process holding the mark" do
      {session, _tracer} = start_session()
      pid = start_process(fn -> put(true, session) end)

      assert served_or_ended?(pid, session)
    end

    test "is true for a process that inherited the mark" do
      {session, _tracer} = start_session()
      put(true, session)
      pid = start_process(fn -> :ok end)

      assert served_or_ended?(pid, session)
    end

    test "stays true after the mark is cleared" do
      {session, _tracer} = start_session()

      pid =
        start_process(fn ->
          put(true, session)
          put(false, session)
        end)

      assert served_or_ended?(pid, session)
    end

    # Bandit does this between the requests of a keep-alive connection.
    test "stays true after the process dictionary is cleared" do
      {session, _tracer} = start_session()

      pid =
        start_process(fn ->
          put(true, session)
          put(false, session)
          Enum.each(Process.get_keys(), &Process.delete/1)
        end)

      assert served_or_ended?(pid, session)
    end

    test "is false for a process started after the mark was cleared" do
      {session, _tracer} = start_session()
      put(true, session)
      put(false, session)
      pid = start_process(fn -> :ok end)

      refute served_or_ended?(pid, session)
    end

    test "is true for a process that has ended" do
      {session, _tracer} = start_session()
      pid = spawn(fn -> :ok end)
      monitor = Process.monitor(pid)
      assert_receive {:DOWN, ^monitor, :process, ^pid, _reason}, @receive_timeout

      assert served_or_ended?(pid, session)
    end

    # With no data model there's no session to protect, so nothing is refused for its caller.
    test "is false with no trace session, even for a process that has ended" do
      pid = spawn(fn -> :ok end)
      monitor = Process.monitor(pid)
      assert_receive {:DOWN, ^monitor, :process, ^pid, _reason}, @receive_timeout

      refute served_or_ended?(pid, nil)
    end
  end

  describe "put/2" do
    test "marks the calling process" do
      {session, _tracer} = start_session()

      assert put(true, session) == :ok
      assert marked?(session)
    end

    test "clears the mark" do
      {session, _tracer} = start_session()
      put(true, session)

      assert put(false, session) == :ok
      refute marked?(session)
    end

    test "passes the mark to a process started while it is set" do
      {session, _tracer} = start_session()
      put(true, session)

      assert marked_in_spawned_process(session)
    end

    test "doesn't pass the mark to a process started after it is cleared" do
      {session, _tracer} = start_session()
      put(true, session)
      put(false, session)

      refute marked_in_spawned_process(session)
    end

    test "does nothing with no trace session" do
      assert put(true, nil) == :ok
      refute marked?(nil)
    end

    test "raises when the tracer has ended, since the mark would silently not be set" do
      {session, tracer} = start_session()
      monitor = Process.monitor(tracer)
      Process.exit(tracer, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^tracer, :killed}, @receive_timeout

      assert_error RuntimeError,
                   "can't mark this process as working for a session: Hologram.Auth.SpawnMark isn't running",
                   fn -> put(true, session) end
    end

    test "clearing the mark doesn't raise when the tracer has ended" do
      {session, tracer} = start_session()
      monitor = Process.monitor(tracer)
      Process.exit(tracer, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^tracer, :killed}, @receive_timeout

      assert put(false, session) == :ok
    end
  end

  describe "restore/2" do
    test "sets the mark" do
      {session, _tracer} = start_session()

      assert restore(true, session) == :ok
      assert marked?(session)
    end

    test "clears the mark" do
      {session, _tracer} = start_session()
      put(true, session)

      assert restore(false, session) == :ok
      refute marked?(session)
    end

    test "does nothing with no trace session" do
      assert restore(true, nil) == :ok
    end

    test "doesn't raise when the tracer has ended" do
      {session, tracer} = start_session()
      monitor = Process.monitor(tracer)
      Process.exit(tracer, :kill)
      assert_receive {:DOWN, ^monitor, :process, ^tracer, :killed}, @receive_timeout

      assert restore(true, session) == :ok
    end
  end
end
