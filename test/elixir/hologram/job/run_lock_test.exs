defmodule Hologram.Job.RunLockTest do
  use Hologram.Test.BasicCase, async: true

  import ExUnit.CaptureLog
  import Hologram.Job.RunLock

  alias Hologram.DB.Config
  alias Hologram.Entity
  alias Hologram.Job.RunLock
  alias Hologram.Test.ClosingTCP
  alias Hologram.Test.CountingListener
  alias Hologram.Test.TCPProxy
  alias Postgrex.SimpleConnection

  # What a run selects the database tests by: they are the ones that need a server.
  @moduletag :database

  # Each one its own session, which is what a lock is held by - and what a second worker, on this
  # node or another, would be.
  defp start_session(opts \\ []) do
    start_supervised!(Supervisor.child_spec({RunLock, opts}, id: make_ref(), restart: :temporary))
  end

  # Started behind a proxy that refuses connections until the test opens it, trying again often
  # enough for a test to sit through several tries. Each try logs, so a test that leaves it
  # refusing stops it inside its log capture.
  defp start_refused_session(opts \\ []) do
    proxy = start_proxy()
    opts = Keyword.merge([port: TCPProxy.port(proxy), reconnect_backoff: 50], opts)

    {proxy, start_session(opts)}
  end

  defp start_proxy do
    start_supervised!(Supervisor.child_spec(TCPProxy, id: make_ref()))
  end

  defp start_open_proxy do
    proxy = start_proxy()
    TCPProxy.open(proxy)

    proxy
  end

  defp session_state(session) do
    {_state_name, %{state: {RunLock, state}}} = :sys.get_state(session)

    state
  end

  # A session whose link has gone silent: nothing is forwarded either way and nothing is closed.
  defp start_silenced_session do
    proxy = start_open_proxy()
    session = start_session(port: TCPProxy.port(proxy))

    await_connected(session)
    TCPProxy.freeze(proxy)

    session
  end

  defp message_queue_len(pid) do
    {:message_queue_len, length} = Process.info(pid, :message_queue_len)

    length
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

    # The claim takes the lock while holding the job's row, which every other node's claim of that
    # row waits on - a server that does not answer must not hold them there for good.
    test "exits and ends the connection when the server does not answer within 5 seconds" do
      session = start_silenced_session()
      monitor_ref = Process.monitor(session)

      assert {:killed, _call} = catch_exit(acquire(session, Entity.generate_id()))
      assert_receive {:DOWN, ^monitor_ref, :process, ^session, :killed}, 1_000
    end

    # Jobs running at once queue their lock calls on one connection, and one waiting behind slow
    # statements the server still answers must not count the wait against its own bound. Three
    # statements of 2 seconds ahead of it make it wait about 6 - past a bound counted from the call,
    # inside one counted per statement.
    test "gives a call queued behind others the whole bound for its own statement" do
      session = start_session()
      watcher = start_session()
      await_connected(session)

      first = Task.async(fn -> query!(session, "SELECT pg_sleep(2)") end)

      # In flight on the server, so the two below queue behind it rather than ahead.
      wait_until(fn ->
        %Postgrex.Result{rows: [[count]]} =
          query!(
            watcher,
            "SELECT count(*) FROM pg_stat_activity WHERE datname = current_database() AND query = 'SELECT pg_sleep(2)' AND state = 'active'"
          )

        count == "1"
      end)

      queued =
        for length <- 1..2 do
          task = Task.async(fn -> query!(session, "SELECT pg_sleep(2)") end)
          wait_until(fn -> message_queue_len(session) == length end)

          task
        end

      assert acquire(session, Entity.generate_id())
      results = Task.await_many([first | queued], 10_000)

      assert Enum.all?(results, &match?(%Postgrex.Result{}, &1))
      assert Process.alive?(session)
    end

    # Every call waiting behind a statement the server leaves unanswered exits with it - which is
    # what rolls back a claim waiting there and frees the job's row for the other nodes.
    test "exits every call queued behind a statement the server does not answer" do
      session = start_silenced_session()
      monitor_ref = Process.monitor(session)

      # The connection serves one call at a time and the server answers neither, so whichever goes
      # first, the other waits behind it until the kill.
      calls =
        for _index <- 1..2 do
          Task.async(fn -> catch_exit(acquire(session, Entity.generate_id())) end)
        end

      assert [{:killed, _first}, {:killed, _second}] = Task.await_many(calls, 10_000)
      assert_receive {:DOWN, ^monitor_ref, :process, ^session, :killed}, 1_000
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

  describe "await_connected/1" do
    test "answers at once when the connection has its session" do
      assert await_connected(start_session()) == :ok
    end

    test "waits while the database refuses connections, until the session has its settings" do
      capture_log(fn ->
        {proxy, session} = start_refused_session(parameters: [idle_session_timeout: "60000"])

        task = Task.async(fn -> await_connected(session) end)
        refute Task.yield(task, 200)

        TCPProxy.open(proxy)

        assert Task.await(task) == :ok
        assert %Postgrex.Result{rows: [["0"]]} = query!(session, "SHOW idle_session_timeout")
      end)
    end

    test "answers every caller waiting" do
      capture_log(fn ->
        {proxy, session} = start_refused_session()

        tasks = for _caller <- 1..2, do: Task.async(fn -> await_connected(session) end)
        assert [{_first, nil}, {_second, nil}] = Task.yield_many(tasks, 200)

        TCPProxy.open(proxy)

        assert Task.await_many(tasks) == [:ok, :ok]
      end)
    end

    test "exits when the connection ends before it has a session" do
      capture_log(fn ->
        {_proxy, session} = start_refused_session()
        test_pid = self()

        {caller, monitor_ref} =
          spawn_monitor(fn ->
            send(test_pid, :waiting)
            await_connected(session)
          end)

        assert_receive :waiting
        wait_until(fn -> length(session_state(session).waiting) == 1 end)

        :ok = :gen_statem.stop(session)

        assert_receive {:DOWN, ^monitor_ref, :process, ^caller, {:normal, _call}}, 2_000
      end)
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

  describe "init/1" do
    test "bounds the session settings by the first statement timeout" do
      assert {:ok, %{setup_timeout_ms: timeout_ms}} = init(nil)
      assert timeout_ms == Config.first_statement_timeout_ms()
    end

    test "bounds each call's statement by 5 seconds" do
      assert {:ok, %{call_timeout_ms: 5_000}} = init(nil)
    end
  end

  describe "handle_connect/1" do
    # Nobody waiting on the session gives up, so nothing else would notice a link that went silent
    # as it opened - the worker would wait for as long as the operating system keeps the socket.
    test "ends the connection when the server leaves the session settings unanswered" do
      {:ok, state} = init(nil)

      {pid, ref} =
        spawn_monitor(fn ->
          {:query, _statement, _state} = handle_connect(%{state | setup_timeout_ms: 100})

          Process.sleep(:infinity)
        end)

      assert_receive {:DOWN, ^ref, :process, ^pid, :killed}, 2_000
    end

    test "leaves the connection up once the session settings are applied" do
      {:ok, state} = init(nil)
      test_pid = self()

      {pid, ref} =
        spawn_monitor(fn ->
          {:query, _statement, state} = handle_connect(%{state | setup_timeout_ms: 100})
          {:noreply, _state} = handle_result([], state)
          send(test_pid, :answered)

          Process.sleep(:infinity)
        end)

      # Armed before the answer, so a kill left armed would land inside the window.
      assert_receive :answered, 2_000
      refute_receive {:DOWN, ^ref, :process, ^pid, _reason}, 200

      Process.exit(pid, :kill)
    end
  end

  describe "handle_result/2" do
    # A session without the settings is the one a server can end under a run still going.
    test "ends the connection when the session settings are refused" do
      {:ok, state} = init(nil)

      assert_raise Postgrex.Error, fn ->
        handle_result(%Postgrex.Error{message: "refused"}, state)
      end
    end
  end

  describe "release/2" do
    test "exits and ends the connection when the server does not answer within 5 seconds" do
      session = start_silenced_session()
      monitor_ref = Process.monitor(session)

      assert {:killed, _call} = catch_exit(release(session, Entity.generate_id()))
      assert_receive {:DOWN, ^monitor_ref, :process, ^session, :killed}, 1_000
    end

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
    # A release left waiting on a link gone silent would hold the worker for as long as the
    # operating system keeps retransmitting, with this node running nothing.
    test "exits and ends the connection when the server does not answer within 5 seconds" do
      session = start_silenced_session()
      monitor_ref = Process.monitor(session)

      assert {:killed, _call} = catch_exit(release_all(session))
      assert_receive {:DOWN, ^monitor_ref, :process, ^session, :killed}, 1_000
    end

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
    # What a node that stops leaves behind: a session that ended, and with it every lock it held.
    test "frees the session's locks when the connection stops" do
      id = Entity.generate_id()
      holder = start_session()

      acquire(holder, id)
      :ok = :gen_statem.stop(holder)

      # Stopping closes the socket, and the server frees the lock once it notices.
      other = start_session()
      wait_until(fn -> acquire(other, id) end)
    end

    # As a peer that resets the connection right after accepting it can make it fail.
    test "keeps trying a connect whose socket fails as it opens" do
      peer = start_supervised!(CountingListener)

      log =
        capture_log(fn ->
          session =
            start_session(
              port: CountingListener.port(peer),
              reconnect_backoff: 50,
              socket_options: ClosingTCP.socket_options()
            )

          monitor_ref = Process.monitor(session)

          wait_until(fn -> CountingListener.accepted(peer) >= 3 end)

          refute_received {:DOWN, ^monitor_ref, :process, ^session, _reason}

          :gen_statem.stop(session)
        end)

      assert log =~ "tcp setopts: invalid argument - :einval"
    end

    test "keeps trying while the database refuses connections" do
      capture_log(fn ->
        {_proxy, session} = start_refused_session()
        monitor_ref = Process.monitor(session)

        refute_receive {:DOWN, ^monitor_ref, :process, ^session, _reason}, 500

        :gen_statem.stop(session)
      end)
    end

    # Without a session there is no socket to send the statement on, and a caller that did not wait
    # must not take the connection down.
    test "fails a call made before it has a session, and stays up" do
      capture_log(fn ->
        {proxy, session} = start_refused_session(idle_interval: 100)

        assert_raise Postgrex.Error, ~r/has no session yet/, fn ->
          acquire(session, Entity.generate_id())
        end

        # The failed call arms the idle ping while there is no socket, which the backoff being
        # below the idle interval keeps from firing - the connection still connects.
        Process.sleep(200)
        TCPProxy.open(proxy)

        assert await_connected(session) == :ok
        assert acquire(session, Entity.generate_id())
      end)
    end

    # What the worker beside it relies on: a session that ended took its locks with it, so the
    # process holding it must not carry on as if it still had them.
    test "ends when its session ends" do
      session = start_session()
      %Postgrex.Result{rows: [[backend_pid]]} = query!(session, "SELECT pg_backend_pid()")
      monitor_ref = Process.monitor(session)

      capture_log(fn ->
        query!(start_session(), "SELECT pg_terminate_backend(#{backend_pid})")

        assert_receive {:DOWN, ^monitor_ref, :process, ^session, {:shutdown, :connection_lost}},
                       30_000
      end)
    end

    test "ends when its link drops, and the server frees its locks" do
      id = Entity.generate_id()
      proxy = start_open_proxy()
      session = start_session(port: TCPProxy.port(proxy))
      monitor_ref = Process.monitor(session)

      assert acquire(session, id)

      capture_log(fn ->
        TCPProxy.close_all(proxy)

        assert_receive {:DOWN, ^monitor_ref, :process, ^session, {:shutdown, :connection_lost}},
                       2_000
      end)

      other = start_session()
      wait_until(fn -> acquire(other, id) end)
    end

    # Nothing calls the connection after it connects, so only the ping it arms itself notices.
    test "ends when its link goes silent with nothing in flight" do
      proxy = start_open_proxy()

      session =
        start_session(
          port: TCPProxy.port(proxy),
          idle_interval: 100,
          ping_timeout: 100,
          reconnect_backoff: 50,
          sync_connect: true
        )

      monitor_ref = Process.monitor(session)

      capture_log(fn ->
        TCPProxy.freeze(proxy)

        assert_receive {:DOWN, ^monitor_ref, :process, ^session, {:shutdown, :connection_lost}},
                       2_000
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

    # A platform without the user timeout keeps it at 0.
    test "sets the session's user timeout where the server's platform has one" do
      assert %Postgrex.Result{rows: [[timeout]]} =
               query!(start_session(), "SHOW tcp_user_timeout")

      assert timeout in ["0", "60000"]
    end

    # A call arriving while the idle ping is in flight waits for the ping, which the connection's
    # bound on statements doesn't cover.
    test "bounds the idle ping by 5 seconds" do
      session = start_session()
      await_connected(session)

      assert {_state_name, %{protocol: %Postgrex.Protocol{ping_timeout: 5_000}}} =
               :sys.get_state(session)
    end

    test "registers the connection under the given name" do
      name = __MODULE__.NamedSession

      pid = start_supervised!({RunLock, name: name})

      assert Process.whereis(name) == pid
      assert acquire(name, Entity.generate_id())
    end
  end
end
