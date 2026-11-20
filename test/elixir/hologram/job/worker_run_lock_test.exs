defmodule Hologram.Job.WorkerRunLockTest do
  # The one worker behaviour that needs a server: what it does with the run locks it finds held as
  # it starts. Apart from Hologram.Job.WorkerTest, which runs without a database.
  use Hologram.Test.BasicCase, async: true

  import ExUnit.CaptureLog

  alias Hologram.Entity
  alias Hologram.Job.RunLock
  alias Hologram.Job.Worker
  alias Hologram.Test.TCPProxy

  @moduletag :database

  defp start_run_lock do
    start_supervised!(Supervisor.child_spec(RunLock, id: make_ref()))
  end

  # A worker restarted on its own finds its predecessor's lock still held on a session that is
  # still up, and the row of the run that crashed would look live for good.
  test "gives up every run lock its connection holds as it starts" do
    id = Entity.generate_id()
    run_lock = start_run_lock()
    other = start_run_lock()

    assert RunLock.acquire(run_lock, id)

    start_supervised!(
      {Worker,
       queued: fn _job_type, _skip_ids, _count -> [] end,
       run_lock: run_lock,
       sweep: fn _job_types, _skip_ids -> :ok end}
    )

    wait_until(fn -> RunLock.acquire(other, id) end)
  end

  # While the database is away nothing can be claimed, and a worker looking anyway would crash on
  # every look.
  test "waits for its run lock connection before anything else" do
    test_pid = self()
    proxy = start_supervised!(TCPProxy)
    port = TCPProxy.port(proxy)

    capture_log(fn ->
      run_lock =
        start_supervised!(
          Supervisor.child_spec({RunLock, port: port, reconnect_backoff: 50}, id: make_ref())
        )

      queued = fn _job_type, _skip_ids, _count ->
        send(test_pid, :looked)
        []
      end

      worker =
        start_supervised!(
          {Worker,
           poll_interval_ms: 20,
           queued: queued,
           run_lock: run_lock,
           sweep: fn _job_types, _skip_ids -> :ok end}
        )

      refute_receive :looked, 300
      assert Process.alive?(worker)

      TCPProxy.open(proxy)

      assert_receive :looked, 2_000
    end)
  end
end
