defmodule Hologram.Job.Runner do
  @moduledoc false

  # Runs one job: claims its row, calls its run/1 under whoever enqueued it, and records what
  # happened. In three transactions rather than one, because run/1 reaches outside the database and
  # must not hold a connection while it does, and because the claim has to be visible to every
  # other node before the work starts - which is what stops two nodes running one job.

  alias Hologram.DB.Connection
  alias Hologram.DB.EntityOperations

  @doc """
  Claims the job of the given type with the given id for this worker: reads its row locked, and
  moves it from queued to running in one transaction.

  Returns `{:claimed, job}` with the row as this worker claimed it, or `:taken` when the row is not
  queued any more - another worker claimed it first, it has already run, or it is gone.

  The claim is the framework's own write, made without an acting user: a job type grants no
  operation for it, and whose job it is has already been decided by whoever enqueued it.
  """
  @spec claim(module, String.t()) :: {:claimed, struct} | :taken
  def claim(job_type, id) do
    {:ok, result} =
      Connection.transaction(fn ->
        # Locked, so a second worker asking at the same moment waits here until this transaction
        # ends, then reads the row as it was committed - running - and answers that it is taken.
        case EntityOperations.get(job_type, id, lock: true) do
          %{status: :queued} = job ->
            :ok = EntityOperations.update(job_type, id, %{status: :running})

            {:claimed, %{job | status: :running}}

          _not_queued ->
            :taken
        end
      end)

    result
  end
end
