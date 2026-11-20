defmodule Hologram.Job.Runner do
  @moduledoc false

  # Runs one job: claims its row, calls its run/1 under whoever enqueued it, and records what
  # happened. In three transactions rather than one, because run/1 reaches outside the database and
  # must not hold a connection while it does, and because the claim has to be visible to every
  # other node before the work starts - which is what stops two nodes running one job.
  #
  # The job's run lock (see Hologram.Job.RunLock) is held for the whole run, taken inside
  # the claim's transaction and given up once the outcome is recorded - so a running row whose lock
  # nobody holds is one whose run was cut short.

  import Hologram.Query, only: [filter: 2, sort: 2, take: 2]

  alias Hologram.Auth.Context
  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.EntityOperations
  alias Hologram.Job.RunLock

  # What the row of a run cut short says. Nothing recorded how far run/1 got, so it claims nothing
  # either way - and the run that knew is gone.
  @cut_short_error "the run was cut short before its outcome was recorded - the node stopped, the run crashed or was killed, its lock connection was lost, or the outcome write failed - so run/1 may have done all, part or none of its work"

  # Set while the claim's transaction holds a run lock it has not committed yet, so a claim that
  # raises after taking the lock knows to give it back.
  @uncommitted_lock_key {__MODULE__, :uncommitted_lock}

  @doc """
  Claims the job of the given type with the given id for this worker: reads its row locked, takes
  its run lock on the given RunLock connection, and moves it from queued to running in one
  transaction.

  Returns `{:claimed, job}` with the row as this worker claimed it, `:taken` when the row is not
  queued any more - another worker claimed it first, it has already run, or it is gone - or
  `:locked` when the row is queued but another session holds its run lock, so it stays queued for
  a later try.

  The lock is taken before the claim commits, so whoever reads the row as running finds it held.
  A claim that raises or exits after taking it gives it back, and raises or exits as it was going
  to even when giving it back exits - the lock went with the connection then. Taking the lock exits
  when the server leaves it unanswered for 5 seconds, which ends the RunLock connection.

  The claim is the framework's own write, made without an acting user: a job type grants no
  operation for it, and whose job it is has already been decided by whoever enqueued it.
  """
  @spec claim(module, String.t(), GenServer.server()) :: {:claimed, struct} | :taken | :locked
  def claim(job_type, id, run_lock) do
    {:ok, result} = Connection.transaction(fn -> claim_row(job_type, id, run_lock) end)

    Process.delete(@uncommitted_lock_key)

    result
  catch
    kind, reason ->
      if Process.delete(@uncommitted_lock_key),
        do: release_quietly(run_lock, lock_name(job_type, id))

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
  Runs the job of the given type with the given id once: claims it, calls its run/1 as the user who
  created it, and records what happened on its row.

  Returns `:done` or `:failed` for a job this worker ran, `:taken` when the job was not queued any
  more, or `:locked` when it is queued under a run lock another session holds (see claim/3).

  The job's run lock is held on the given RunLock connection from the claim until the outcome is
  recorded, and given up then even when recording it raises - until the outcome commits, the row
  must look like a run in progress. Giving it up never replaces the answer or the error: a release
  that exits means the connection, and the lock with it, is gone already.

  The outcome is recorded only on a row still running. One a sweep on another node has already
  failed keeps that verdict - its lock was lost mid-run, so this run looked abandoned - and a row
  that is gone has nothing to record it on. The answer is what run/1 did either way.
  """
  @spec process(module, String.t(), GenServer.server()) :: :done | :failed | :taken | :locked
  def process(job_type, id, run_lock) do
    case claim(job_type, id, run_lock) do
      not_claimed when not_claimed in [:taken, :locked] ->
        not_claimed

      {:claimed, job} ->
        try do
          outcome = invoke(job)

          record_outcome(job_type, id, outcome)

          outcome_status(outcome)
        after
          release_quietly(run_lock, lock_name(job_type, id))
        end
    end
  end

  @doc """
  Returns the name of the run lock of the job of the given type with the given id.

  Named by the type as well as the id, since an id is unique only within its type's table - a
  browser picks the id of a row it creates, so two job types can hold one id. Sharing a lock, the
  two would stack on one session when both run on a node, and the release the worker makes for a
  run that went down would free the other's.

  Frozen for good, like the key derived from it (see Hologram.Job.RunLock.key/1).
  """
  @spec lock_name(module, String.t()) :: String.t()
  def lock_name(job_type, id), do: inspect(job_type) <> ":" <> id

  @doc """
  Returns the oldest queued jobs of the given job type, at most the given count of them, oldest
  first, leaving out the ones whose ids are in the given set.

  Reads at most the count plus the set's size, so the read stays bounded however many jobs are
  queued, and the jobs left out never cost one the count would otherwise answer with.
  """
  @spec queued(module, MapSet.t(String.t()), non_neg_integer) :: list(struct)
  def queued(job_type, skip_ids, count) do
    # Read raw, because a worker has no acting user - which is also why the rows are read through
    # the ordinary verb rather than a statement of its own: with nobody acting there is nothing to
    # filter, and the rows come back as the structs run/1 is handed. The same goes for sweep/2.
    #
    # The queued and the running rows are read apart, two reads where one would do, because only
    # this one is bounded - the index on status and creation time keeps both cheap (see
    # Hologram.DB.IndexPlan.framework_needs/1).
    limit = count + MapSet.size(skip_ids)

    job_type
    |> filter(status == :queued)
    |> sort(created_at)
    |> take(^limit)
    |> DB.read()
    |> Enum.reject(&MapSet.member?(skip_ids, &1.id))
    |> Enum.take(count)
  end

  @doc """
  Fails each running job of the given job types whose run lock no session holds - a run cut short,
  by a node that stopped, a run that crashed or was killed, a lost lock connection, or an outcome
  write that failed - with an error saying so, and returns :ok.

  Leaves out the jobs whose ids are in the given set: the ones the caller is running itself, whose
  locks its own session holds.
  """
  @spec sweep(list(module), MapSet.t(String.t())) :: :ok
  def sweep(job_types, skip_ids) do
    Enum.each(job_types, fn job_type ->
      job_type
      |> filter(status == :running)
      |> DB.read()
      |> Enum.reject(&MapSet.member?(skip_ids, &1.id))
      |> Enum.each(&sweep_row(job_type, &1.id))
    end)
  end

  # Whatever run/1 does, the run goes on to record it: a job that raises is a failed job rather than
  # a crashed run, and the exception is what the row records.
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
  # A queued row whose run lock another session holds is left queued and tried again later. The
  # lock of a queued job is otherwise free, so only two things get here: a key shared by two jobs,
  # where the job runs once the one it shares the key with has finished, and a claim on another node
  # that failed after taking the lock and has not given it back yet. Answered apart from a row that
  # is not queued, since only this one is worth leaving out of the next look: the other is running
  # or over, so a look for queued jobs never answers it again.
  defp claim_row(job_type, id, run_lock) do
    case EntityOperations.get(job_type, id, lock: :no_key_update) do
      %{status: :queued} = job ->
        if RunLock.acquire(run_lock, lock_name(job_type, id)) do
          Process.put(@uncommitted_lock_key, true)

          :ok = EntityOperations.update(job_type, id, %{status: :running})

          {:claimed, %{job | status: :running}}
        else
          :locked
        end

      _not_queued ->
        :taken
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

  # Gives up a run lock on the way out of a claim or a run, whether or not it ended in an error. A
  # release that exits - the connection gone, or killed for leaving it unanswered - is let go: the
  # lock went with the session either way, and the runs go down with the connection. What it
  # must not do is replace the error the claim or the run is leaving with.
  defp release_quietly(run_lock, name) do
    RunLock.release(run_lock, name)
  catch
    :exit, _reason -> :ok
  end

  # Raises what the query answers with otherwise, the way the other statements a sweep runs do.
  defp run_lock_free?(name) do
    case Connection.query("SELECT pg_try_advisory_xact_lock($1)", [RunLock.key(name)]) do
      {:ok, %Postgrex.Result{rows: [[free?]]}} -> free?
      {:error, error} -> raise error
    end
  end

  # Each row is judged in a transaction of its own, whose advisory lock is the job's run lock taken
  # for the transaction alone: taken, nobody holds it, so nobody is running the job. The try form,
  # so a sweep never waits on a run - and with the advisory lock always tried before the row is
  # waited on, and a claim waiting only on the row, the two cannot wait on each other.
  #
  # The row is read again under the row lock: a run that recorded its outcome and gave its lock up
  # after the list was read is not running any more.
  defp sweep_row(job_type, id) do
    {:ok, :ok} =
      Connection.transaction(fn ->
        with true <- run_lock_free?(lock_name(job_type, id)),
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
