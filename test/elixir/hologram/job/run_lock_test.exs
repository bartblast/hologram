defmodule Hologram.Job.RunLockTest do
  use Hologram.Test.BasicCase, async: true

  import ExUnit.CaptureLog
  import Hologram.Job.RunLock

  alias Hologram.Entity
  alias Hologram.Job.RunLock
  alias Postgrex.SimpleConnection

  # What a run selects the database tests by: they are the ones that need a server.
  @moduletag :database

  # Each one its own session, which is what a lock is held by - and what a second worker, on this
  # node or another, would be.
  defp start_session(opts \\ []) do
    start_supervised!(Supervisor.child_spec({RunLock, opts}, id: make_ref(), restart: :temporary))
  end

  defp query!(session, statement) do
    [result] = SimpleConnection.call(session, {:query, statement}, :infinity)

    result
  end

  describe "acquire/2" do
    test "takes the lock of a job nobody holds" do
      assert acquire(start_session(), Entity.generate_id())
    end

    test "does not take the lock of a job another session holds" do
      id = Entity.generate_id()

      assert acquire(start_session(), id)
      refute acquire(start_session(), id)
    end

    test "takes the locks of two jobs on one session" do
      session = start_session()

      assert acquire(session, Entity.generate_id())
      assert acquire(session, Entity.generate_id())
    end

    test "stacks a lock one session takes twice, so it takes two releases to free" do
      id = Entity.generate_id()
      holder = start_session()
      other = start_session()

      assert acquire(holder, id)
      assert acquire(holder, id)

      release(holder, id)
      refute acquire(other, id)

      release(holder, id)
      assert acquire(other, id)
    end
  end

  describe "key/1" do
    test "names one job by the same key every time" do
      id = Entity.generate_id()

      assert key(id) == key(id)
    end

    test "names two jobs by different keys" do
      assert key(Entity.generate_id()) != key(Entity.generate_id())
    end

    # Frozen for good: nodes of two versions deriving different keys would miss each other's locks.
    # One key of each sign, so that reading the bytes unsigned would not pass either.
    test "derives the key from the id the way every version does" do
      assert key("00000000-0000-0000-0000-000000000000") == 4_103_822_260_172_771_572
      assert key("00000000-0000-0000-0000-000000000003") == -6_367_754_148_487_292_905
    end
  end

  describe "handle_result/2" do
    # A session without the settings is the one a server can end under a run still going.
    test "ends the connection when the session settings are refused" do
      assert_raise Postgrex.Error, fn ->
        handle_result(%Postgrex.Error{message: "refused"}, %{from: nil})
      end
    end
  end

  describe "release/2" do
    test "frees the lock of the job for other sessions" do
      id = Entity.generate_id()
      holder = start_session()

      acquire(holder, id)

      assert release(holder, id) == :ok
      assert acquire(start_session(), id)
    end

    test "leaves the session's other locks held" do
      released_id = Entity.generate_id()
      kept_id = Entity.generate_id()
      holder = start_session()
      other = start_session()

      acquire(holder, released_id)
      acquire(holder, kept_id)

      release(holder, released_id)

      refute acquire(other, kept_id)
    end

    test "answers :ok for a lock the session does not hold, leaving another session's" do
      id = Entity.generate_id()
      other = start_session()

      acquire(other, id)

      assert release(start_session(), id) == :ok
      refute acquire(start_session(), id)
    end
  end

  describe "release_all/1" do
    test "frees every lock the session holds" do
      first_id = Entity.generate_id()
      second_id = Entity.generate_id()
      holder = start_session()
      other = start_session()

      acquire(holder, first_id)
      acquire(holder, second_id)

      assert release_all(holder) == :ok
      assert acquire(other, first_id)
      assert acquire(other, second_id)
    end
  end

  describe "start_link/1" do
    # What a node that stops or a worker that crashes leaves behind: a session that ended, and with
    # it every lock it held.
    test "frees the session's locks when the connection stops" do
      id = Entity.generate_id()
      holder = start_session()

      acquire(holder, id)
      :ok = :gen_statem.stop(holder)

      # Stopping closes the socket, and the server frees the lock once it notices.
      other = start_session()
      wait_until(fn -> acquire(other, id) end)
    end

    # What the worker beside it relies on: a session that ended took its locks with it, so the
    # process holding it must not carry on as if it still had them.
    test "ends when its session ends" do
      session = start_session()
      %Postgrex.Result{rows: [[backend_pid]]} = query!(session, "SELECT pg_backend_pid()")
      monitor_ref = Process.monitor(session)

      capture_log(fn ->
        query!(start_session(), "SELECT pg_terminate_backend(#{backend_pid})")

        assert_receive {:DOWN, ^monitor_ref, :process, ^session, _reason}, 30_000
      end)
    end

    # A session ended by the server's idle timeout would free the lock of a run still going.
    # Started with a timeout of its own, since the server's default is already off.
    test "turns off the session's idle timeout" do
      session = start_session(parameters: [idle_session_timeout: "60000"])

      assert %Postgrex.Result{rows: [["0"]]} = query!(session, "SHOW idle_session_timeout")
    end

    test "sets the session's keepalives" do
      statement =
        "SELECT current_setting('tcp_keepalives_idle'), current_setting('tcp_keepalives_interval'), current_setting('tcp_keepalives_count')"

      assert %Postgrex.Result{rows: [["30", "10", "3"]]} = query!(start_session(), statement)
    end

    test "registers the connection under the given name" do
      name = __MODULE__.NamedSession

      pid = start_supervised!({RunLock, name: name})

      assert Process.whereis(name) == pid
      assert acquire(name, Entity.generate_id())
    end
  end
end
