# credo:disable-for-this-file Credo.Check.Readability.Specs
# A job type whose run/1 does whatever its outcome attribute names, so that one fixture covers
# every answer the runner has to classify and both halves of the authority rule. It declares
# allow :read and no allow :create, which is what makes a create under an acting user a denial
# rather than the teaching refusal a type declaring nothing gets.
defmodule Hologram.Test.Fixtures.Job.Module3 do
  use Hologram.Job

  alias Hologram.Auth
  alias Hologram.Auth.Context
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.EntityOperations
  alias Hologram.DB.Mapper
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2
  alias Hologram.Test.Fixtures.Job.Module1

  attribute :outcome, :enum,
    values: [
      :create_next,
      :create_row,
      :delete_self,
      :error,
      :exit,
      :garbage,
      :hang,
      :ok,
      :ok_tuple,
      :raise,
      :record_actor,
      :recreated,
      :rescheduled,
      :superseded,
      :swept,
      :throw
    ]

  allow :read

  @impl Hologram.Job
  def run(%{outcome: :create_next}) do
    Hologram.Job.create!(Module1, [], trust: true)

    :ok
  end

  def run(%{outcome: :create_row}) do
    %{c: "by job"}
    |> Entity2.new()
    |> Hologram.DB.create!()

    :ok
  end

  # Takes its own row away, so recording the outcome has no row to write to.
  def run(%{outcome: :delete_self} = job) do
    :ok = EntityOperations.delete(__MODULE__, job.id)

    :ok
  end

  def run(%{outcome: :error}), do: {:error, :smtp_down}

  def run(%{outcome: :exit}), do: exit(:boom)

  def run(%{outcome: :garbage}), do: nil

  def run(%{outcome: :hang}), do: Process.sleep(:infinity)

  def run(%{outcome: :ok}), do: :ok

  def run(%{outcome: :ok_tuple}), do: {:ok, :sent}

  def run(%{outcome: :raise}), do: raise("boom")

  def run(%{outcome: :record_actor}) do
    Process.put(:ran_as, Auth.user_id())
    Process.put(:ran_in_session?, Context.session?())

    :ok
  end

  # Replaces its row with a new one under the same id, running the same attempt number, and then
  # fails - standing for a run that lost its lock while its job was deleted and created again.
  def run(%{outcome: :recreated} = job) do
    :ok = EntityOperations.delete(__MODULE__, job.id)

    Hologram.Job.create!(__MODULE__, [id: job.id, outcome: :ok], trust: true)

    :ok = EntityOperations.update(__MODULE__, job.id, %{attempt: job.attempt, status: :running})

    # The clock behind this time ticks in milliseconds, or coarser, and the two creates can land
    # on one tick here, as they couldn't with a run that had lost its lock in between.
    {:ok, _result} =
      Connection.query(
        ~s|UPDATE "hologram_data"."#{Mapper.table_name(__MODULE__)}" | <>
          ~s|SET "server_created_at" = "server_created_at" + interval '1 second' WHERE "id" = $1|,
        [Codec.encode(job.id, :id)]
      )

    {:error, :too_late}
  end

  # Moves its own due time, standing for server code rescheduling the job while it runs.
  def run(%{outcome: :rescheduled} = job) do
    later = DateTime.add(DateTime.utc_now(), 1, :hour)

    :ok = EntityOperations.update(__MODULE__, job.id, %{scheduled_at: later})

    :ok
  end

  # Moves its row on to the next attempt and then fails, standing for a run that lost its lock, was
  # swept back into the queue and claimed again by another worker while it was still going.
  def run(%{outcome: :superseded} = job) do
    :ok = EntityOperations.update(__MODULE__, job.id, %{attempt: job.attempt + 1})

    {:error, :too_late}
  end

  # Fails its own row, standing for a sweep on another node that found the run's lock gone.
  def run(%{outcome: :swept} = job) do
    :ok = EntityOperations.update(__MODULE__, job.id, %{error: "swept", status: :failed})

    :ok
  end

  def run(%{outcome: :throw}), do: throw(:boom)
end
