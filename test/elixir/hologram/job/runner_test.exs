defmodule Hologram.Job.RunnerTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.Job.Runner

  alias Hologram.DB.EntityOperations
  alias Hologram.Entity
  alias Hologram.Job
  alias Hologram.Test.Fixtures.Job.Module1

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
end
