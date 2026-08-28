defmodule Hologram.Job.RunnerTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.Job.Runner
  import Hologram.Test, only: [as_user: 2]

  alias Hologram.Auth
  alias Hologram.DB
  alias Hologram.DB.EntityOperations
  alias Hologram.Entity
  alias Hologram.Job
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2
  alias Hologram.Test.Fixtures.Job.Module1
  alias Hologram.Test.Fixtures.Job.Module3

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

  # The jobs record themselves as they run, newest first, so the order they ran in reads forwards.
  defp ran_order do
    :ran_order
    |> Process.get([])
    |> Enum.reverse()
  end

  describe "claim/2" do
    test "claims a queued job" do
      job = Job.create!(Module1)

      assert {:claimed, claimed_job} = claim(Module1, job.id)

      assert claimed_job.id == job.id
      assert claimed_job.status == :running
      assert EntityOperations.get(Module1, job.id).status == :running
    end

    test "skips a job another worker has claimed" do
      job = Job.create!(Module1)

      assert {:claimed, _job} = claim(Module1, job.id)
      assert claim(Module1, job.id) == :taken
    end

    test "skips a job that has already run" do
      job = Job.create!(Module1)

      :ok = EntityOperations.update(Module1, job.id, %{status: :done})

      assert claim(Module1, job.id) == :taken
      assert EntityOperations.get(Module1, job.id).status == :done
    end

    test "skips a job that is not there" do
      assert claim(Module1, Entity.generate_id()) == :taken
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

  describe "pass/1" do
    test "runs every queued job of a type, oldest first" do
      first = job(:record_order)
      second = job(:record_order)

      # The order the pass reads in is created_at's, and two rows created a moment apart share it
      # wherever the system clock ticks coarsely - so the times are set rather than raced for, and
      # the SECOND job is made the older one, which no insertion order could produce by accident.
      set_created_at(Module3, first.id, ~U[2026-01-01 00:00:01.000000Z])
      set_created_at(Module3, second.id, ~U[2026-01-01 00:00:00.000000Z])

      assert pass([Module3]) == 2

      assert ran_order() == [second.id, first.id]
      assert EntityOperations.get(Module3, first.id).status == :done
      assert EntityOperations.get(Module3, second.id).status == :done
    end

    test "runs the types in the order it was given" do
      module_1_job = Job.create!(Module1)
      module_3_job = job(:record_order)

      assert pass([Module3, Module1]) == 2

      assert ran_order() == [module_3_job.id, module_1_job.id]
    end

    test "runs nothing when nothing is queued" do
      assert pass([Module1, Module3]) == 0
    end

    test "leaves a job another worker has claimed, and does not count it" do
      claimed = job(:ok)
      queued = job(:ok)

      assert {:claimed, _job} = claim(Module3, claimed.id)
      assert pass([Module3]) == 1

      assert EntityOperations.get(Module3, claimed.id).status == :running
      assert EntityOperations.get(Module3, queued.id).status == :done
    end
  end

  describe "process/2" do
    test "runs a queued job to done" do
      job = job(:ok)

      assert process(Module3, job.id) == :done

      row = EntityOperations.get(Module3, job.id)

      assert row.status == :done
      assert row.error == nil
    end

    test "runs a queued job to failed, with the error on its row" do
      job = job(:raise)

      assert process(Module3, job.id) == :failed

      row = EntityOperations.get(Module3, job.id)

      assert row.status == :failed
      assert row.error =~ "** (RuntimeError) boom"
    end

    test "skips a job another worker has claimed" do
      job = job(:ok)

      assert {:claimed, _job} = claim(Module3, job.id)
      assert process(Module3, job.id) == :taken
      assert EntityOperations.get(Module3, job.id).status == :running
    end

    test "records the outcome outside the creating user's authority" do
      user = create_user("recorder@example.com")
      job = job(:ok, user)

      # Module3 grants nobody an update, so an outcome written as the creating user would be
      # denied - which is what makes this an assertion about whose write it is.
      assert as_user(user, fn -> process(Module3, job.id) end) == :done
      assert EntityOperations.get(Module3, job.id).status == :done
    end
  end
end
