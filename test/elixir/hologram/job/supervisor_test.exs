defmodule Hologram.Job.SupervisorTest do
  use Hologram.Test.BasicCase, async: true

  import ExUnit.CaptureLog
  import Hologram.Job.Supervisor

  alias Hologram.DB.Listener
  alias Hologram.Entity
  alias Hologram.Job.RunLock
  alias Hologram.Job.Worker
  alias Hologram.Test.TCPProxy

  defp child_ids do
    {:ok, {_flags, children}} = init([])

    Enum.map(children, & &1.id)
  end

  describe "init/1" do
    test "starts the listener, then the run lock connection, then the runs' supervisor, then the worker" do
      assert child_ids() == [notifications(), RunLock, runs(), Worker]
    end

    test "starts the runs' supervisor under its own name" do
      {:ok, {_flags, children}} = init([])

      assert %{start: {Task.Supervisor, :start_link, [opts]}} =
               Enum.find(children, &(&1.id == runs()))

      assert opts[:name] == runs()
    end

    test "starts the run lock connection under its own name" do
      {:ok, {_flags, children}} = init([])

      assert %{start: {RunLock, :start_link, [opts]}} = Enum.find(children, &(&1.id == RunLock))

      assert opts[:name] == RunLock
    end

    test "starts the worker on both connections and the runs' supervisor, under its own name" do
      {:ok, {_flags, children}} = init([])

      assert %{start: {Worker, :start_link, [opts]}} =
               Enum.find(children, &(&1.id == Worker))

      assert opts[:name] == Worker
      assert opts[:notifications] == notifications()
      assert opts[:run_lock] == RunLock
      assert opts[:runs] == runs()
    end

    # A worker left standing when its listener ends would keep waiting on one that is gone, which
    # nothing reports - it would fall back to its poll and simply be slower for good. Runs left
    # going when their lock connection ends would carry on with their locks gone, looking abandoned.
    test "restarts the runs and the worker with either connection" do
      assert {:ok, {%{strategy: :rest_for_one}, _children}} = init([])
    end
  end

  describe "a lock call the server leaves unanswered" do
    # The run lock connection and the worker as this supervisor starts them, except that the lock
    # connection goes through a proxy the test can silence and every look takes a lock on it.
    # Allowing a single restart is what shows the timeout counts once: the lock connection is
    # killed, and the worker it takes with it is restarted with it rather than on its own. Killed
    # is what tells the timeout apart from a lost session, which ends the connection itself.
    @tag :database
    test "restarts the lock connection and the worker once, and the supervisor stays up" do
      proxy = start_supervised!(TCPProxy)
      TCPProxy.open(proxy)
      port = TCPProxy.port(proxy)
      run_lock = __MODULE__.RunLock
      test_pid = self()

      queued = fn _job_type, _skip_ids, _count ->
        send(test_pid, {:look, self()})
        RunLock.acquire(run_lock, Entity.generate_id())

        []
      end

      children = [
        {RunLock, name: run_lock, port: port},
        Supervisor.child_spec({Task.Supervisor, name: __MODULE__.Runs}, id: __MODULE__.Runs),
        {Worker,
         poll_interval_ms: 50,
         queued: queued,
         run_lock: run_lock,
         runs: __MODULE__.Runs,
         sweep: fn _job_types, _skip_ids -> :ok end}
      ]

      supervisor =
        start_supervised!(%{
          id: :job_tree,
          restart: :temporary,
          start:
            {Supervisor, :start_link, [children, [strategy: :rest_for_one, max_restarts: 1]]},
          type: :supervisor
        })

      supervisor_ref = Process.monitor(supervisor)

      capture_log(fn ->
        assert_receive {:look, worker}, 5_000
        old_run_lock = Process.whereis(run_lock)
        run_lock_ref = Process.monitor(old_run_lock)

        TCPProxy.freeze(proxy)

        assert_receive {:DOWN, ^run_lock_ref, :process, ^old_run_lock, :killed}, 10_000
        assert_receive {:look, new_worker} when new_worker != worker, 5_000

        assert Process.whereis(run_lock) not in [nil, old_run_lock]
        refute_receive {:DOWN, ^supervisor_ref, :process, ^supervisor, _reason}, 200

        stop_supervised!(:job_tree)
      end)
    end

    # As above, except that the lock is taken by a run, in its task, and given up by the worker's
    # own release. The run's call exits when the lock connection is killed. The supervisor most
    # often shuts the worker down first; when the run's DOWN reaches the worker first, its release
    # finds the connection gone and ends the worker too. Either way it's the one restart.
    @tag :database
    test "restarts once when a run's lock call is left unanswered, and the supervisor stays up" do
      proxy = start_supervised!(TCPProxy)
      TCPProxy.open(proxy)
      run_lock = __MODULE__.RunLockOfRuns
      runs = __MODULE__.RunsOfRuns
      worker = __MODULE__.WorkerOfRuns
      test_pid = self()
      {:ok, given?} = Agent.start_link(fn -> false end)

      queued = fn _job_type, _skip_ids, _count ->
        if Agent.get_and_update(given?, &{&1, true}), do: [], else: [%{id: Entity.generate_id()}]
      end

      run = fn _job_type, id ->
        send(test_pid, {:run, self()})

        receive do
          :go -> RunLock.acquire(run_lock, id)
        end

        :done
      end

      children = [
        {RunLock, name: run_lock, port: TCPProxy.port(proxy)},
        Supervisor.child_spec({Task.Supervisor, name: runs}, id: runs),
        {Worker,
         name: worker,
         queued: queued,
         run: run,
         run_lock: run_lock,
         runs: runs,
         sweep: fn _job_types, _skip_ids -> :ok end}
      ]

      supervisor =
        start_supervised!(%{
          id: :job_tree,
          restart: :temporary,
          start:
            {Supervisor, :start_link, [children, [strategy: :rest_for_one, max_restarts: 1]]},
          type: :supervisor
        })

      supervisor_ref = Process.monitor(supervisor)

      capture_log(fn ->
        assert_receive {:run, run_pid}, 5_000
        old_worker = Process.whereis(worker)
        old_run_lock = Process.whereis(run_lock)
        run_lock_ref = Process.monitor(old_run_lock)
        run_ref = Process.monitor(run_pid)

        TCPProxy.freeze(proxy)
        send(run_pid, :go)

        assert_receive {:DOWN, ^run_lock_ref, :process, ^old_run_lock, :killed}, 10_000
        assert_receive {:DOWN, ^run_ref, :process, ^run_pid, _reason}, 5_000

        wait_until(fn -> Process.whereis(worker) not in [nil, old_worker] end)
        assert Process.whereis(run_lock) not in [nil, old_run_lock]
        refute_receive {:DOWN, ^supervisor_ref, :process, ^supervisor, _reason}, 200

        stop_supervised!(:job_tree)
      end)
    end
  end

  describe "a LISTEN the server leaves unanswered" do
    # The listener as this supervisor starts it, through a proxy the test silences before the
    # worker starts - a worker listens as it starts, which leaves no gap to silence the link in.
    # Allowing a single restart is what shows the unanswered LISTEN counts once: the listener is
    # killed before the worker's call gives up, and the worker is restarted with it rather than on
    # its own first.
    @tag :database
    test "restarts the listener and the worker once, and the supervisor stays up" do
      proxy = start_supervised!(TCPProxy)
      TCPProxy.open(proxy)
      notifications = __MODULE__.Notifications
      test_pid = self()

      queued = fn _job_type, _skip_ids, _count ->
        send(test_pid, {:look, self()})

        []
      end

      children = [
        {Listener, name: notifications, port: TCPProxy.port(proxy), sync_connect: true},
        Supervisor.child_spec({Task.Supervisor, name: __MODULE__.ListenerRuns},
          id: __MODULE__.ListenerRuns
        )
      ]

      supervisor =
        start_supervised!(%{
          id: :job_tree,
          restart: :temporary,
          start:
            {Supervisor, :start_link, [children, [strategy: :rest_for_one, max_restarts: 1]]},
          type: :supervisor
        })

      supervisor_ref = Process.monitor(supervisor)
      old_listener = Process.whereis(notifications)
      listener_ref = Process.monitor(old_listener)

      capture_log(fn ->
        TCPProxy.freeze(proxy)

        {:ok, _worker} =
          Supervisor.start_child(
            supervisor,
            {Worker,
             notifications: notifications,
             poll_interval_ms: 50,
             queued: queued,
             release: fn _job_type, _id -> :ok end,
             run: fn _job_type, _id -> :done end,
             runs: __MODULE__.ListenerRuns,
             sweep: fn _job_types, _skip_ids -> :ok end}
          )

        assert_receive {:DOWN, ^listener_ref, :process, ^old_listener, :killed}, 6_000
        assert_receive {:look, _new_worker}, 5_000

        assert Process.whereis(notifications) not in [nil, old_listener]
        refute_receive {:DOWN, ^supervisor_ref, :process, ^supervisor, _reason}, 200

        stop_supervised!(:job_tree)
      end)
    end
  end
end
