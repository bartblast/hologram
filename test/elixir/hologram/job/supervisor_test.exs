defmodule Hologram.Job.SupervisorTest do
  use Hologram.Test.BasicCase, async: true

  import ExUnit.CaptureLog
  import Hologram.Job.Supervisor

  alias Hologram.Entity
  alias Hologram.Job.RunLock
  alias Hologram.Job.Worker
  alias Hologram.Test.TCPProxy

  defp child_ids do
    {:ok, {_flags, children}} = init([])

    Enum.map(children, & &1.id)
  end

  describe "init/1" do
    test "starts the listener, then the run lock connection, then the worker" do
      assert child_ids() == [notifications(), RunLock, Worker]
    end

    test "starts the run lock connection under its own name" do
      {:ok, {_flags, children}} = init([])

      assert %{start: {RunLock, :start_link, [opts]}} = Enum.find(children, &(&1.id == RunLock))

      assert opts[:name] == RunLock
    end

    test "starts the worker on both connections, under its own name" do
      {:ok, {_flags, children}} = init([])

      assert %{start: {Worker, :start_link, [opts]}} =
               Enum.find(children, &(&1.id == Worker))

      assert opts[:name] == Worker
      assert opts[:notifications] == notifications()
      assert opts[:run_lock] == RunLock
    end

    # A worker left standing when its listener ends would keep waiting on one that is gone, which
    # nothing reports - it would fall back to its poll and simply be slower for good. One left
    # standing when its lock connection ends would carry on with runs that look abandoned.
    test "restarts the worker with either connection" do
      assert {:ok, {%{strategy: :rest_for_one}, _children}} = init([])
    end
  end

  describe "a lock call the server leaves unanswered" do
    # The run lock connection and the worker as this supervisor starts them, except that the lock
    # connection goes through a proxy the test can silence and every pass takes a lock on it.
    # Allowing a single restart is what shows the timeout counts once: the lock connection is
    # killed, and the worker it takes with it is restarted with it rather than on its own. Killed
    # is what tells the timeout apart from a lost session, which ends the connection itself.
    @tag :database
    test "restarts the lock connection and the worker once, and the supervisor stays up" do
      port = TCPProxy.closed_port()
      proxy = start_supervised!({TCPProxy, port})
      run_lock = __MODULE__.RunLock
      test_pid = self()

      pass = fn _job_types ->
        send(test_pid, {:pass, self()})
        RunLock.acquire(run_lock, Entity.generate_id())

        0
      end

      children = [
        {RunLock, name: run_lock, port: port},
        {Worker, pass: pass, poll_interval_ms: 50, run_lock: run_lock}
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

      log =
        capture_log(fn ->
          assert_receive {:pass, worker}, 5_000
          old_run_lock = Process.whereis(run_lock)
          run_lock_ref = Process.monitor(old_run_lock)

          TCPProxy.freeze(proxy)

          assert_receive {:DOWN, ^run_lock_ref, :process, ^old_run_lock, :killed}, 10_000
          assert_receive {:pass, new_worker} when new_worker != worker, 5_000

          assert Process.whereis(run_lock) not in [nil, old_run_lock]
          refute_received {:DOWN, ^supervisor_ref, :process, ^supervisor, _reason}

          stop_supervised!(:job_tree)
        end)

      refute log =~ "lost its connection"
    end
  end
end
