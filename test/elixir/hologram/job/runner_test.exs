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
    Module14
    |> Entity.new(email: email)
    |> DB.create!()
  end

  # A job of the outcome fixture, created as the given user or as nobody. Module3 declares no
  # allow :create, so a create under an acting user claims the server's authority - what the run
  # is under is the actor the row carries, which is stamped either way.
  defp job(outcome, user \\ nil) do
    create = fn -> Job.create!(Module3, [outcome: outcome], trust: true) end

    if user, do: as_user(user, create), else: create.()
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
end
