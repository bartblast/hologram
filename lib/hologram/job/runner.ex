defmodule Hologram.Job.Runner do
  @moduledoc false

  # Runs one job: claims its row, calls its run/1 under whoever enqueued it, and records what
  # happened. In three transactions rather than one, because run/1 reaches outside the database and
  # must not hold a connection while it does, and because the claim has to be visible to every
  # other node before the work starts - which is what stops two nodes running one job.
  #
  # For the whole run the worker holds the job's run lock (see Hologram.Job.RunLock), taken inside
  # the claim's transaction and given up once the outcome is recorded - so a running row whose lock
  # nobody holds is one whose run was cut short.

  import Hologram.Query, only: [filter: 2, sort: 2]

  alias Hologram.Auth.Context
  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.EntityOperations
  alias Hologram.Job.RunLock

  # What the row of a run cut short says. Nothing recorded how far run/1 got, so it claims nothing
  # either way - and the worker that knew is gone.
  @cut_short_error "the run was cut short before its outcome was recorded - the node stopped, the worker crashed or lost its connection to the database, or the outcome write failed - so run/1 may have done all, part or none of its work"

  # Set while the claim's transaction holds a run lock it has not committed yet, so a claim that
  # raises after taking the lock knows to give it back.
  @uncommitted_lock_key {__MODULE__, :uncommitted_lock}

  @doc """
  Claims the job of the given type with the given id for this worker: reads its row locked, takes
  its run lock on the given RunLock connection, and moves it from queued to running in one
  transaction.

  Returns `{:claimed, job}` with the row as this worker claimed it, or `:taken` when the row is not
  queued any more - another worker claimed it first, it has already run, or it is gone - or when
  another session holds its run lock.

  The lock is taken before the claim commits, so whoever reads the row as running finds it held.
  A claim that raises or exits after taking it gives it back.

  The claim is the framework's own write, made without an acting user: a job type grants no
  operation for it, and whose job it is has already been decided by whoever enqueued it.
  """
  @spec claim(module, String.t(), GenServer.server()) :: {:claimed, struct} | :taken
  def claim(job_type, id, run_lock) do
    {:ok, result} = Connection.transaction(fn -> claim_row(job_type, id, run_lock) end)

    Process.delete(@uncommitted_lock_key)

    result
  catch
    kind, reason ->
      if Process.delete(@uncommitted_lock_key), do: RunLock.release(run_lock, id)

      :erlang.raise(kind, reason, __STACKTRACE__)
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

  The run locks are taken on the given RunLock connection.

  Before running a type's jobs, it fails each of its running jobs whose run lock no session holds -
  a run cut short, by a node that stopped, a worker that crashed or lost its lock connection, or an
  outcome write that failed - with an error saying so. Those are not counted, since nothing ran.
  """
  @spec pass(list(module), GenServer.server()) :: non_neg_integer
  def pass(job_types, run_lock) do
    Enum.reduce(job_types, 0, fn job_type, count ->
      {running, queued} = read_unfinished(job_type)

      Enum.each(running, &sweep(job_type, &1.id))

      count + Enum.count(queued, &(process(job_type, &1.id, run_lock) != :taken))
    end)
  end

  @doc """
  Runs the job of the given type with the given id once: claims it, calls its run/1 as the user who
  created it, and records what happened on its row.

  Returns `:done` or `:failed` for a job this worker ran, or `:taken` when another worker had it.

  The job's run lock is held on the given RunLock connection from the claim until the outcome is
  recorded, and given up then even when recording it raises - until the outcome commits, the row
  must look like a run in progress.

  The outcome is recorded only on a row still running. One a pass on another node has already
  failed keeps that verdict - its lock was lost mid-run, so this run looked abandoned - and a row
  that is gone has nothing to record it on. The answer is what run/1 did either way.
  """
  @spec process(module, String.t(), GenServer.server()) :: :done | :failed | :taken
  def process(job_type, id, run_lock) do
    case claim(job_type, id, run_lock) do
      :taken ->
        :taken

      {:claimed, job} ->
        try do
          outcome = invoke(job)

          record_outcome(job_type, id, outcome)

          outcome_status(outcome)
        after
          RunLock.release(run_lock, id)
        end
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

  # Locked, so a second worker asking at the same moment waits here until this transaction ends,
  # then reads the row as it was committed - running - and answers that it is taken without
  # touching the run lock. FOR NO KEY UPDATE, like every row lock a run takes: it is the lock the
  # update takes anyway, and a row being inserted with a reference to the job does not hold it up.
  #
  # A queued row whose run lock another session holds is left queued and tried again by a later
  # pass. The lock of a queued job is otherwise free, so only two things get here: a key shared by
  # two jobs, where the job runs once the one it shares the key with has finished, and a claim on
  # another node that failed after taking the lock and has not given it back yet.
  defp claim_row(job_type, id, run_lock) do
    with %{status: :queued} = job <- EntityOperations.get(job_type, id, lock: :no_key_update),
         true <- RunLock.acquire(run_lock, id) do
      Process.put(@uncommitted_lock_key, true)

      :ok = EntityOperations.update(job_type, id, %{status: :running})

      {:claimed, %{job | status: :running}}
    else
      _not_queued_or_locked -> :taken
    end
  end

  defp classify(:ok), do: :done

  defp classify({:ok, _value}), do: :done

  defp classify({:error, reason}), do: {:failed, "run/1 returned {:error, #{inspect(reason)}}"}

  defp classify(other) do
    {:failed, "run/1 must return :ok, {:ok, value} or {:error, reason}, got: #{inspect(other)}"}
  end

  defp outcome_changes(:done), do: %{status: :done}

  defp outcome_changes({:failed, text}), do: %{error: text, status: :failed}

  defp outcome_status(:done), do: :done

  defp outcome_status({:failed, _text}), do: :failed

  # Read raw, because a worker has no acting user - which is also why the rows are read through the
  # ordinary verb rather than a statement of its own: with nobody acting there is nothing to filter,
  # and the rows come back as the structs run/1 is handed. The running and the queued in one read,
  # since a pass runs on every write the app makes.
  defp read_unfinished(job_type) do
    job_type
    |> filter(status in [:queued, :running])
    |> sort(created_at)
    |> DB.read()
    |> Enum.split_with(&(&1.status == :running))
  end

  # The framework's own write, like the claim: a job type grants nobody an update, and the outcome
  # is not the creating user's to authorize. Reached only after invoke/1 has put the actor back, so
  # nothing of the run is still in scope.
  #
  # Read locked, so a sweep failing the row at the same moment either commits first - and its
  # verdict stands - or waits and finds the row recorded.
  defp record_outcome(job_type, id, outcome) do
    {:ok, :ok} =
      Connection.transaction(fn ->
        case EntityOperations.get(job_type, id, lock: :no_key_update) do
          %{status: :running} ->
            :ok = EntityOperations.update(job_type, id, outcome_changes(outcome))

          _swept_or_gone ->
            :ok
        end
      end)

    :ok
  end

  defp run_lock_free?(id) do
    {:ok, %Postgrex.Result{rows: [[free?]]}} =
      Connection.query("SELECT pg_try_advisory_xact_lock($1)", [RunLock.key(id)])

    free?
  end

  # Each row is judged in a transaction of its own, whose advisory lock is the job's run lock taken
  # for the transaction alone: taken, nobody holds it, so nobody is running the job. The try form,
  # so a sweep never waits on a run - and with the advisory lock always tried before the row is
  # waited on, and a claim waiting only on the row, the two cannot wait on each other.
  #
  # The row is read again under the row lock: a run that recorded its outcome and gave its lock up
  # after the list was read is not running any more.
  defp sweep(job_type, id) do
    {:ok, :ok} =
      Connection.transaction(fn ->
        with true <- run_lock_free?(id),
             %{status: :running} <- EntityOperations.get(job_type, id, lock: :no_key_update) do
          :ok =
            EntityOperations.update(job_type, id, %{error: @cut_short_error, status: :failed})
        else
          _held_or_not_running -> :ok
        end
      end)

    :ok
  end
end
