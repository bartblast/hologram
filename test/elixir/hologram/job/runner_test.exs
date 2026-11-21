defmodule Hologram.Job.RunnerTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.Job.Runner
  import Hologram.Test, only: [as_user: 2]

  alias Hologram.Auth
  alias Hologram.DB
  alias Hologram.DB.EntityOperations
  alias Hologram.Entity
  alias Hologram.Job
  alias Hologram.Job.RunLock
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2
  alias Hologram.Test.Fixtures.Job.Module1
  alias Hologram.Test.Fixtures.Job.Module3

  # The worker's lock connection, a session of its own beside the sandboxed one: advisory locks are
  # the database's, so what it holds is seen by every other session whatever the sandbox has not
  # committed.
  setup do
    [run_lock: start_supervised!(RunLock)]
  end

  # Whether some other session - another worker, or a sweep - could take the job's run lock.
  defp lock_free?(job) do
    other = start_supervised!(Supervisor.child_spec(RunLock, id: make_ref()))
    name = lock_name(job.__struct__, job.id)
    free? = RunLock.acquire(other, name)

    if free?, do: RunLock.release(other, name)

    free?
  end

  defp create_user(email) do
    %{email: email}
    |> Module14.new()
    |> DB.create!()
  end

  # A job of the outcome fixture, created as the given user or as nobody. Module3 declares no
  # allow :create, so a create under an acting user claims the server's authority - what the run
  # is under is the actor the row carries, which is stamped either way.
  defp job(outcome, user \\ nil) do
    create = fn -> Job.create!(Module3, [outcome: outcome], trust: true) end

    if user, do: as_user(user, create), else: create.()
  end

  describe "claim/3" do
    test "claims a queued job", %{run_lock: run_lock} do
      job = Job.create!(Module1)

      assert {:claimed, claimed_job} = claim(Module1, job.id, run_lock)

      assert claimed_job.id == job.id
      assert claimed_job.status == :running
      assert EntityOperations.get(Module1, job.id).status == :running
    end

    test "skips a job another worker has claimed", %{run_lock: run_lock} do
      job = Job.create!(Module1)

      assert {:claimed, _job} = claim(Module1, job.id, run_lock)
      assert claim(Module1, job.id, run_lock) == :taken
    end

    test "holds the run lock of the job it claims", %{run_lock: run_lock} do
      job = Job.create!(Module1)

      assert {:claimed, _job} = claim(Module1, job.id, run_lock)

      refute lock_free?(job)
    end

    # A browser picks the id of a row it creates, so a job of another type can hold one id too.
    test "claims a job while one of another type with the same id runs", %{run_lock: run_lock} do
      first = Job.create!(Module1)
      second = Job.create!(Module3, [id: first.id, outcome: :ok], trust: true)
      other = start_supervised!(Supervisor.child_spec(RunLock, id: make_ref()))

      assert {:claimed, _job} = claim(Module1, first.id, other)
      assert {:claimed, _job} = claim(Module3, second.id, run_lock)
    end

    test "takes no run lock for a job that is not queued", %{run_lock: run_lock} do
      job = Job.create!(Module1)

      :ok = EntityOperations.update(Module1, job.id, %{status: :done})

      assert claim(Module1, job.id, run_lock) == :taken
      assert lock_free?(job)
    end

    # Only a key two jobs share gets here, or a claim on another node that failed and has not given
    # the lock back yet - and the job is left queued for a later try.
    test "leaves a queued job whose run lock another session holds", %{run_lock: run_lock} do
      job = Job.create!(Module1)
      other = start_supervised!(Supervisor.child_spec(RunLock, id: make_ref()))

      assert RunLock.acquire(other, lock_name(Module1, job.id))

      assert claim(Module1, job.id, run_lock) == :locked
      assert EntityOperations.get(Module1, job.id).status == :queued
    end

    test "skips a job that has already run", %{run_lock: run_lock} do
      job = Job.create!(Module1)

      :ok = EntityOperations.update(Module1, job.id, %{status: :done})

      assert claim(Module1, job.id, run_lock) == :taken
      assert EntityOperations.get(Module1, job.id).status == :done
    end

    test "skips a job that is not there", %{run_lock: run_lock} do
      assert claim(Module1, Entity.generate_id(), run_lock) == :taken
    end

    test "leaves a queued job with no due time", %{run_lock: run_lock} do
      job = Job.create!(Module1)

      :ok = EntityOperations.update(Module1, job.id, %{scheduled_at: nil})

      assert claim(Module1, job.id, run_lock) == :taken
      assert EntityOperations.get(Module1, job.id).status == :queued
    end

    test "counts the attempt", %{run_lock: run_lock} do
      job = Job.create!(Module1)

      assert {:claimed, claimed_job} = claim(Module1, job.id, run_lock)

      assert claimed_job.attempt == 1
      assert EntityOperations.get(Module1, job.id).attempt == 1
    end

    test "counts on from the attempts the job has had", %{run_lock: run_lock} do
      job = Job.create!(Module1)

      :ok = EntityOperations.update(Module1, job.id, %{attempt: 3})

      assert {:claimed, %{attempt: 4}} = claim(Module1, job.id, run_lock)
    end

    # The look that named it read it before another node put it back to wait.
    test "leaves a queued job that isn't due yet", %{run_lock: run_lock} do
      job = Job.create!(Module1)

      set_scheduled_at(Module1, job.id, DateTime.add(DateTime.utc_now(), 1, :hour))

      assert claim(Module1, job.id, run_lock) == :taken

      row = EntityOperations.get(Module1, job.id)

      assert row.status == :queued
      assert row.attempt == 0
      assert lock_free?(job)
    end
  end

  describe "invoke/1" do
    test "answers done for :ok" do
      assert invoke(job(:ok)) == :done
    end

    test "answers done for an ok tuple" do
      assert invoke(job(:ok_tuple)) == :done
    end

    test "answers failed for an error tuple" do
      assert invoke(job(:error)) == {:failed, "run/1 returned {:error, :smtp_down}"}
    end

    test "answers failed for a raise, with the exception and where it was raised" do
      assert {:failed, text} = invoke(job(:raise))

      assert text =~ "** (RuntimeError) boom"
      assert text =~ "module_3.ex"
    end

    test "answers failed for a throw" do
      assert {:failed, text} = invoke(job(:throw))

      assert text =~ "** (throw) :boom"
    end

    test "answers failed for an exit" do
      assert {:failed, text} = invoke(job(:exit))

      assert text =~ "** (exit) :boom"
    end

    test "answers failed for any other return" do
      assert invoke(job(:garbage)) ==
               {:failed, "run/1 must return :ok, {:ok, value} or {:error, reason}, got: nil"}
    end

    test "runs run/1 as the user who created the job" do
      user = create_user("runner@example.com")

      assert invoke(job(:record_actor, user)) == :done
      assert Process.get(:ran_as) == user.id

      # The actor the run was given is put back afterwards, so a worker's next job starts clean.
      assert Auth.user_id() == nil
    end

    test "runs a job created with no actor raw" do
      assert invoke(job(:record_actor)) == :done
      assert Process.get(:ran_as) == nil
    end

    test "answers failed for a write the creating user may not make" do
      user = create_user("writer@example.com")

      assert {:failed, text} = invoke(job(:create_row, user))

      assert text =~ "** (Hologram.AccessDeniedError) not allowed to create"
      assert DB.read(Entity2) == []
    end

    test "lands a write of a job created with no actor" do
      assert invoke(job(:create_row)) == :done
      assert [%Entity2{c: "by job"}] = DB.read(Entity2)
    end
  end

  describe "process/3" do
    # A lock request exits only when its connection is gone, taking the lock with it if it was
    # granted - and the run must go down with it rather than carry on with no lock held, so nothing
    # on the way may swallow the exit.
    test "lets a lock request that exits end the run" do
      job = job(:ok)

      dead = spawn(fn -> :ok end)
      monitor_ref = Process.monitor(dead)
      assert_receive {:DOWN, ^monitor_ref, :process, ^dead, _reason}

      assert catch_exit(process(Module3, job.id, dead))
    end

    test "leaves a queued job whose run lock another session holds", %{run_lock: run_lock} do
      job = job(:ok)
      other = start_supervised!(Supervisor.child_spec(RunLock, id: make_ref()))

      assert RunLock.acquire(other, lock_name(Module3, job.id))

      assert process(Module3, job.id, run_lock) == :locked
      assert EntityOperations.get(Module3, job.id).status == :queued
    end

    test "runs a queued job to done", %{run_lock: run_lock} do
      job = job(:ok)

      assert process(Module3, job.id, run_lock) == :done

      row = EntityOperations.get(Module3, job.id)

      assert row.status == :done
      assert row.error == nil
    end

    test "runs a queued job to failed, with the error on its row", %{run_lock: run_lock} do
      job = job(:raise)

      assert process(Module3, job.id, run_lock) == :failed

      row = EntityOperations.get(Module3, job.id)

      assert row.status == :failed
      assert row.error =~ "** (RuntimeError) boom"
    end

    test "skips a job another worker has claimed", %{run_lock: run_lock} do
      job = job(:ok)

      assert {:claimed, _job} = claim(Module3, job.id, run_lock)
      assert process(Module3, job.id, run_lock) == :taken
      assert EntityOperations.get(Module3, job.id).status == :running
    end

    test "gives up the run lock once the job is done", %{run_lock: run_lock} do
      job = job(:ok)

      assert process(Module3, job.id, run_lock) == :done
      assert lock_free?(job)
    end

    test "gives up the run lock once the job has failed", %{run_lock: run_lock} do
      job = job(:raise)

      assert process(Module3, job.id, run_lock) == :failed
      assert lock_free?(job)
    end

    # The lock is the claim's, which process did not make - giving it up would leave a run in
    # progress looking abandoned.
    test "keeps the run lock of a job another claim holds", %{run_lock: run_lock} do
      job = job(:ok)

      assert {:claimed, _job} = claim(Module3, job.id, run_lock)
      assert process(Module3, job.id, run_lock) == :taken

      refute lock_free?(job)
    end

    # Another node's sweep failed the row while run/1 ran - its lock was lost mid-run, so the run
    # looked abandoned - and that verdict is what the row keeps.
    test "keeps the failure a sweep recorded while the job ran", %{run_lock: run_lock} do
      job = job(:swept)

      assert process(Module3, job.id, run_lock) == :done

      row = EntityOperations.get(Module3, job.id)

      assert row.status == :failed
      assert row.error == "swept"
      assert lock_free?(job)
    end

    test "records nothing for a job whose row is gone", %{run_lock: run_lock} do
      job = job(:delete_self)

      assert process(Module3, job.id, run_lock) == :done

      assert EntityOperations.get(Module3, job.id) == nil
      assert lock_free?(job)
    end

    test "records the outcome outside the creating user's authority", %{run_lock: run_lock} do
      user = create_user("recorder@example.com")
      job = job(:ok, user)

      # Module3 grants nobody an update, so an outcome written as the creating user would be
      # denied - which is what makes this an assertion about whose write it is.
      assert as_user(user, fn -> process(Module3, job.id, run_lock) end) == :done
      assert EntityOperations.get(Module3, job.id).status == :done
    end
  end

  describe "lock_name/2" do
    # A browser picks the id of a row it creates, so two job types can hold one id - and two runs
    # sharing a lock would stack on one session, where the release for one frees the other's.
    test "names the run locks of two job types' jobs with one id apart" do
      id = Entity.generate_id()

      assert lock_name(Module1, id) != lock_name(Module3, id)
    end

    test "names a job's run lock the same way every time" do
      assert lock_name(Module1, "01a1f90b-3867-7fb8-b6ec-32bdc35da5d7") ==
               "Hologram.Test.Fixtures.Job.Module1:01a1f90b-3867-7fb8-b6ec-32bdc35da5d7"
    end
  end

  describe "queued/3" do
    # Each job is made due a second before the one created before it, an order no insertion order
    # could produce by accident.
    defp jobs_oldest_first(count) do
      for index <- 1..count do
        job = job(:ok)
        set_scheduled_at(Module3, job.id, DateTime.add(~U[2026-01-01 00:00:00.000000Z], -index))

        job
      end
      |> Enum.reverse()
      |> Enum.map(& &1.id)
    end

    defp queued_ids(skip_ids, count) do
      Module3
      |> queued(MapSet.new(skip_ids), count)
      |> Enum.map(& &1.id)
    end

    test "answers the longest due queued jobs of the type, longest due first" do
      [first, second, _third] = jobs_oldest_first(3)

      assert queued_ids([], 2) == [first, second]
    end

    # A browser's clock can be set as far back as it likes, and created_at is what it says.
    test "doesn't let a job with a backdated creation time jump the queue" do
      [first, second] = jobs_oldest_first(2)

      set_created_at(Module3, second, ~U[2000-01-01 00:00:00.000000Z])

      assert queued_ids([], 2) == [first, second]
    end

    test "leaves out queued jobs that aren't due yet" do
      [waiting, due] = jobs_oldest_first(2)

      set_scheduled_at(Module3, waiting, DateTime.add(DateTime.utc_now(), 1, :hour))

      assert queued_ids([], 5) == [due]
    end

    test "answers only jobs of the given type" do
      Job.create!(Module1)
      [job_id] = jobs_oldest_first(1)

      assert queued_ids([], 5) == [job_id]
    end

    test "leaves out jobs that are not queued" do
      [running, done, queued] = jobs_oldest_first(3)

      :ok = EntityOperations.update(Module3, running, %{status: :running})
      :ok = EntityOperations.update(Module3, done, %{status: :done})

      assert queued_ids([], 5) == [queued]
    end

    test "leaves out the given ids, and still answers the count" do
      [first, second, third, fourth] = jobs_oldest_first(4)

      assert queued_ids([first, third], 2) == [second, fourth]
    end

    test "answers nothing when nothing is queued" do
      assert queued(Module3, MapSet.new(), 5) == []
    end

    test "answers nothing for a count of 0" do
      jobs_oldest_first(1)

      assert queued(Module3, MapSet.new(), 0) == []
    end
  end

  describe "sweep/2" do
    # Running with no lock held, the way a node that stopped mid-run leaves it.
    defp abandoned_job do
      job = Job.create!(Module1)
      :ok = EntityOperations.update(Module1, job.id, %{status: :running})

      job
    end

    test "fails a running job whose run lock nobody holds" do
      job = abandoned_job()

      assert sweep([Module1], MapSet.new()) == :ok

      row = EntityOperations.get(Module1, job.id)

      assert row.status == :failed
      assert row.error =~ "the run was cut short before its outcome was recorded"
    end

    test "leaves a running job whose run lock another session holds", %{run_lock: run_lock} do
      job = Job.create!(Module1)

      assert {:claimed, _job} = claim(Module1, job.id, run_lock)
      assert sweep([Module1], MapSet.new()) == :ok

      assert EntityOperations.get(Module1, job.id).status == :running
    end

    test "leaves a running job whose id it is given" do
      job = abandoned_job()

      assert sweep([Module1], MapSet.new([job.id])) == :ok

      assert EntityOperations.get(Module1, job.id).status == :running
    end

    test "leaves queued jobs" do
      job = Job.create!(Module1)

      assert sweep([Module1], MapSet.new()) == :ok

      assert EntityOperations.get(Module1, job.id).status == :queued
    end

    test "sweeps every type it is given" do
      module_1_job = abandoned_job()
      module_3_job = job(:ok)
      :ok = EntityOperations.update(Module3, module_3_job.id, %{status: :running})

      assert sweep([Module1, Module3], MapSet.new()) == :ok

      assert EntityOperations.get(Module1, module_1_job.id).status == :failed
      assert EntityOperations.get(Module3, module_3_job.id).status == :failed
    end
  end
end
