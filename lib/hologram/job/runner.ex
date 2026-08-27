defmodule Hologram.Job.Runner do
  @moduledoc false

  # Runs one job: claims its row, calls its run/1 under whoever enqueued it, and records what
  # happened. In three transactions rather than one, because run/1 reaches outside the database and
  # must not hold a connection while it does, and because the claim has to be visible to every
  # other node before the work starts - which is what stops two nodes running one job.

  import Hologram.Query, only: [filter: 2, order_by: 2]

  alias Hologram.Auth.Context
  alias Hologram.DB
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

  @doc """
  Calls the given job's run/1 with it, as the user who created it - so its reads are filtered and
  its writes evaluated as that user's, and raw for a job created with no actor.

  Returns `:done` when run/1 answered `:ok` or `{:ok, value}` - the value is not kept, since what a
  job did is in the rows it wrote - or `{:failed, text}` for `{:error, reason}`, for a raise, throw
  or exit, and for any other return, each with the text that goes on the row.
  """
  @spec invoke(struct) :: :done | {:failed, String.t()}
  def invoke(job) do
    Context.with_actor(job.actor_id, fn -> attempt(job) end)
  end

  @doc """
  Runs every queued job of the given job types - oldest first within a type, the types in the order
  given - and returns how many jobs this worker ran, which does not count the ones another worker
  had already taken.

  A job created while the pass runs is left for the next one: what it reads is the queue as it
  stood when it asked.
  """
  @spec pass(list(module)) :: non_neg_integer
  def pass(job_types) do
    Enum.reduce(job_types, 0, fn job_type, count ->
      count + ran_count(job_type)
    end)
  end

  @doc """
  Runs the job of the given type with the given id once: claims it, calls its run/1 as the user who
  created it, and records what happened on its row.

  Returns `:done` or `:failed` for a job this worker ran, or `:taken` when another worker had it.
  """
  @spec process(module, String.t()) :: :done | :failed | :taken
  def process(job_type, id) do
    case claim(job_type, id) do
      :taken ->
        :taken

      {:claimed, job} ->
        outcome = invoke(job)

        record_outcome(job_type, id, outcome)

        outcome_status(outcome)
    end
  end

  # Whatever run/1 does, the worker goes on: a job that raises is a failed job rather than a failed
  # worker, and the exception is what the row records.
  defp attempt(job) do
    job_type = job.__struct__

    classify(job_type.run(job))
  rescue
    error -> {:failed, Exception.format(:error, error, __STACKTRACE__)}
  catch
    kind, reason -> {:failed, Exception.format(kind, reason, __STACKTRACE__)}
  end

  defp classify(:ok), do: :done

  defp classify({:ok, _value}), do: :done

  defp classify({:error, reason}), do: {:failed, "run/1 returned {:error, #{inspect(reason)}}"}

  defp classify(other) do
    {:failed, "run/1 must return :ok, {:ok, value} or {:error, reason}, got: #{inspect(other)}"}
  end

  defp outcome_status(:done), do: :done

  defp outcome_status({:failed, _text}), do: :failed

  # The framework's own write, like the claim: a job type grants nobody an update, and the outcome
  # is not the creating user's to authorize. Reached only after invoke/1 has put the actor back, so
  # nothing of the run is still in scope.
  # Read raw, because a worker has no acting user - which is also why the queue is read through the
  # ordinary verb rather than a statement of its own: with nobody acting there is nothing to filter,
  # and the rows come back as the structs run/1 is handed.
  defp ran_count(job_type) do
    job_type
    |> filter(status: :queued)
    |> order_by(:created_at)
    |> DB.read()
    |> Enum.count(&(process(job_type, &1.id) != :taken))
  end

  defp record_outcome(job_type, id, :done) do
    :ok = EntityOperations.update(job_type, id, %{status: :done})
  end

  defp record_outcome(job_type, id, {:failed, text}) do
    :ok = EntityOperations.update(job_type, id, %{error: text, status: :failed})
  end
end
