defmodule Hologram.Job.WorkerRunLockTest do
  # The one worker behaviour that needs a server: what it does with the run locks it finds held as
  # it starts. Apart from Hologram.Job.WorkerTest, which runs without a database.
  use Hologram.Test.BasicCase, async: true

  alias Hologram.Entity
  alias Hologram.Job.RunLock
  alias Hologram.Job.Worker

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

    start_supervised!({Worker, pass: fn _job_types -> 0 end, run_lock: run_lock})

    wait_until(fn -> RunLock.acquire(other, id) end)
  end
end
