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

  import Hologram.Query, only: [filter: 2, sort: 2, take: 2, trust: 1]

  alias Hologram.Auth.Context
  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.DB.EntityOperations
  alias Hologram.Job
  alias Hologram.Job.RunLock

  # What the row of a run cut short says. Nothing recorded how far run/1 got, so it claims nothing
  # either way - and the run that knew is gone.
  @cut_short_error "the run was cut short before its outcome was recorded - the node stopped, the run crashed or was killed, its lock connection was lost, or the outcome write failed - so run/1 may have done all, part or none of its work"

  # The wait after a job's first failed attempt, the factor it grows by each attempt, and the longest
  # it gets. With the default 10 attempts: 30 s, 2 min, 8 min, 32 min, 2 h 8 min, then 6 h four
  # times, about 27 hours in all. The power stops at 5, which is already past the longest wait, so
  # it stays small however many attempts a job type allows.
  @retry_base_ms :timer.seconds(30)
  @retry_growth 4
  @retry_max_exponent 5
  @retry_max_ms :timer.hours(6)

  # Which of the given single-key advisory locks other sessions hold in this database. A lock of the
  # session asking is left out, since pg_try_advisory_xact_lock takes that one again and calls it
  # free, and sweep_row/2 is what the answer stands in for. PostgreSQL files a bigint key as its
  # high and low halves.
  @held_keys_statement """
  SELECT (classid::bigint << 32) | objid::bigint
  FROM pg_catalog.pg_locks
  WHERE locktype = 'advisory'
    AND objsubid = 1
    AND granted
    AND pid <> pg_catalog.pg_backend_pid()
    AND database = (
      SELECT oid FROM pg_catalog.pg_database WHERE datname = pg_catalog.current_database()
    )
    AND ((classid::bigint << 32) | objid::bigint) = ANY($1::bigint[])
  """

  # Set while the claim's transaction holds a run lock it has not committed yet, so a claim that
  # raises after taking the lock knows to give it back.
  @uncommitted_lock_key {__MODULE__, :uncommitted_lock}

  @doc """
  Claims the job of the given type with the given id for this worker: reads its row locked, takes
  its run lock on the given RunLock connection, and moves it from queued to running in one
  transaction, counting the attempt.

  Returns `{:claimed, job}` with the row as this worker claimed it, `:taken` when the row is not
  queued and due any more - another worker claimed it first, it has already run, it is gone, or it
  was put back to wait for a later time - or `:locked` when the row is queued but another session
  holds its run lock, so it stays queued for a later try.

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
  Calls the given job's run/1 with it, as whoever created it: as the recorded user, raw with no
  session for a job marked run_as_server, and otherwise as an anonymous session, so a job with
  neither mark is judged by the rules rather than trusted.

  Returns `:done` when run/1 answered `:ok` or `{:ok, value}` - the value is not kept, since what a
  job did is in the rows it wrote - or `{:failed, text}` for `{:error, reason}`, for a raise, throw
  or exit, and for any other return, each with the text that goes on the row.
  """
  @spec invoke(struct) :: :done | {:failed, String.t()}
  def invoke(%{actor_id: nil, run_as_server: true} = job) do
    Context.without_session(fn -> attempt(job) end)
  end

  def invoke(job) do
    Context.with_actor(job.actor_id, fn -> attempt(job) end)
  end

  @doc """
  Runs one attempt of the job of the given type with the given id: claims it, calls its run/1 as the
  user who created it, and records what happened on its row. A failed attempt puts the job back in
  the queue to wait for its next one, or leaves it failed when it was the last.

  Returns `:done` or `:failed` for an attempt this worker ran, `:taken` when the job was not queued and
  due any more, or `:locked` when it is queued under a run lock another session holds (see claim/3).

  The job's run lock is held on the given RunLock connection from the claim until the outcome is
  recorded, and given up then even when recording it raises - until the outcome commits, the row
  must look like a run in progress. Giving it up never replaces the answer or the error: a release
  that exits means the connection, and the lock with it, is gone already.

  The outcome is recorded only on a row still running this attempt. One a sweep on another node
  has already judged keeps that verdict - its lock was lost mid-run, so this run looked abandoned -
  even when another worker has since claimed the job's next attempt, and a row that is gone has
  nothing to record it on. The answer is what run/1 did either way.
  """
  @spec process(module, String.t(), GenServer.server()) :: :done | :failed | :taken | :locked
  def process(job_type, id, run_lock) do
    case claim(job_type, id, run_lock) do
      not_claimed when not_claimed in [:taken, :locked] ->
        not_claimed

      {:claimed, job} ->
        try do
          outcome = invoke(job)

          record_outcome(job, outcome)

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
  Returns the queued jobs of the given job type that are due, at most the given count of them,
  the longest due first, leaving out the ones whose ids are in the given set.

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
    # this one is bounded - the index on status and due time keeps both cheap (see
    # Hologram.DB.IndexPlan.framework_needs/1).
    #
    # Due by this node's clock, since a query has no database clock to ask. A job stamped by a node
    # whose clock runs ahead is found here once this one catches up, or at the next poll after it.
    limit = count + MapSet.size(skip_ids)
    now = DateTime.utc_now()

    job_type
    |> filter(status == :queued and scheduled_at <= ^now)
    |> sort(scheduled_at)
    |> take(^limit)
    |> trust()
    |> DB.read()
    |> Enum.reject(&MapSet.member?(skip_ids, &1.id))
    |> Enum.take(count)
  end

  @doc """
  Returns how long, in milliseconds, a job waits after the given failed attempt: 30 seconds after
  the first, four times longer after each one after it, up to 6 hours, give or take a random 10%,
  so that jobs that failed together don't all try again together.
  """
  @spec retry_delay_ms(non_neg_integer) :: pos_integer
  def retry_delay_ms(attempt) do
    exponent = min(max(attempt, 1) - 1, @retry_max_exponent)
    delay = min(@retry_base_ms * @retry_growth ** exponent, @retry_max_ms)
    jitter = div(delay, 10)

    delay + Enum.random(-jitter..jitter)
  end

  @doc """
  Records a failed attempt for each running job of the given job types whose run lock no session
  holds - a run cut short, by a node that stopped, a run that crashed or was killed, a lost lock
  connection, or an outcome write that failed - with an error saying so, and returns :ok. Such a job
  goes back in the queue to wait for its next attempt, or is left failed when it was its last.

  Leaves out the jobs whose ids are in the given set: the ones the caller is running itself, whose
  locks its own session holds.
  """
  @spec sweep(list(module), MapSet.t(String.t())) :: :ok
  def sweep(job_types, skip_ids) do
    Enum.each(job_types, fn job_type ->
      job_type
      |> filter(status == :running)
      |> trust()
      |> DB.read()
      |> Enum.map(& &1.id)
      |> Enum.reject(&MapSet.member?(skip_ids, &1))
      |> reject_held(job_type)
      |> Enum.each(&sweep_row(job_type, &1))
    end)
  end

  @doc """
  Records a failed attempt for the job of the given type with the given id, whose run was killed
  for passing the given time limit in milliseconds, and returns :ok.

  Called once the run is dead and its lock given up, and judged like a sweep's row: a run that
  recorded its outcome before the kill landed keeps it, and so does a row already swept, or one
  another worker has claimed again, whose lock it holds.
  """
  @spec time_out(module, String.t(), pos_integer) :: :ok
  def time_out(job_type, id, timeout) do
    fail_abandoned(
      job_type,
      id,
      "the run passed its time limit of #{timeout} ms and was killed, so run/1 may have done all, part or none of its work"
    )
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
  # lock of a queued job is otherwise free, so only three things get here: a key shared by two jobs,
  # where the job runs once the one it shares the key with has finished, a claim on another node
  # that failed after taking the lock and has not given it back yet, and a job a failed run just
  # put back whose run has not given its lock up yet, seen by a node whose clock runs far enough
  # ahead to find it due. Answered apart from a row that is not queued, since only this one is worth
  # leaving out of the next look: the other is running or over, so a look for queued jobs never
  # answers it again.
  #
  # A queued row that isn't due counts as taken too: the look that named it read it before it was
  # put back to wait, and running it now would skip the wait and spend an attempt. No look answers
  # it again until it is due.
  defp claim_row(job_type, id, run_lock) do
    job = EntityOperations.get(job_type, id, lock: :no_key_update)

    if claimable?(job) do
      claim_queued(job, run_lock)
    else
      :taken
    end
  end

  defp claim_queued(%job_type{id: id} = job, run_lock) do
    if RunLock.acquire(run_lock, lock_name(job_type, id)) do
      Process.put(@uncommitted_lock_key, true)

      changes = %{attempt: job.attempt + 1, status: :running}

      :ok = EntityOperations.update(job_type, id, changes)

      {:claimed, Map.merge(job, changes)}
    else
      :locked
    end
  end

  # A row with no due time is one no look lists either, since the look's range leaves it out.
  defp claimable?(%{status: :queued, scheduled_at: %DateTime{} = scheduled_at}) do
    DateTime.compare(scheduled_at, DateTime.utc_now()) != :gt
  end

  defp claimable?(_not_queued), do: false

  # What a failed attempt writes: the job waits for its next attempt while it has any left. The
  # attempt was counted when it was claimed, so the job's limit is reached on the attempt that
  # equals it.
  defp attempt_failed_changes(job_type, attempt, text) do
    if attempt < Job.max_attempts(job_type) do
      scheduled_at = DateTime.add(DateTime.utc_now(), retry_delay_ms(attempt), :millisecond)

      %{error: text, scheduled_at: scheduled_at, status: :queued}
    else
      %{error: text, status: :failed}
    end
  end

  defp classify(:ok), do: :done

  defp classify({:ok, _value}), do: :done

  defp classify({:error, reason}), do: {:failed, "run/1 returned {:error, #{inspect(reason)}}"}

  defp classify(other) do
    {:failed, "run/1 must return :ok, {:ok, value} or {:error, reason}, got: #{inspect(other)}"}
  end

  # A run that ended done leaves no error of an earlier attempt behind.
  defp outcome_changes(_job, :done), do: %{error: nil, status: :done}

  defp outcome_changes(%job_type{attempt: attempt}, {:failed, text}) do
    attempt_failed_changes(job_type, attempt, text)
  end

  defp outcome_status(:done), do: :done

  defp outcome_status({:failed, _text}), do: :failed

  # The framework's own write, like the claim: a job type grants nobody an update, and the outcome
  # is not the creating user's to authorize. Reached only after invoke/1 has put the actor back, so
  # nothing of the run is still in scope.
  #
  # Read locked, so a sweep judging the row at the same moment either commits first - and its
  # verdict stands - or waits and finds the row recorded.
  #
  # Only for the attempt this run claimed: running alone doesn't say whose run it is, since a run
  # that lost its lock can be swept back into the queue and claimed again while it is still going.
  # That holds because only the claim moves `attempt`, and only upward - the framework's alone to
  # write (see Hologram.Job). The server's creation time tells apart a row deleted and created again
  # under the same id, whose count starts over: it is set once per row, and no update can move it.
  defp record_outcome(
         %job_type{id: id, attempt: attempt, server_created_at: created_at} = job,
         outcome
       ) do
    {:ok, :ok} =
      Connection.transaction(fn ->
        case EntityOperations.get(job_type, id, lock: :no_key_update) do
          %{status: :running, attempt: ^attempt, server_created_at: ^created_at} ->
            :ok = EntityOperations.update(job_type, id, outcome_changes(job, outcome))

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

  # Almost every running job on another node holds its lock, and judging each one takes a
  # transaction, so the ones held are left out with one read. Only a filter: sweep_row/2 still
  # judges the rest, and a lock released after this read is found at the next sweep.
  defp reject_held([], _job_type), do: []

  defp reject_held(ids, job_type) do
    keys = Map.new(ids, &{&1, RunLock.key(lock_name(job_type, &1))})

    held_keys =
      keys
      |> Map.values()
      |> held_keys()
      |> MapSet.new()

    Enum.reject(ids, &MapSet.member?(held_keys, Map.fetch!(keys, &1)))
  end

  # A role refused the read filters nothing, so the sweep still works, one row at a time. The
  # server logs the refusal each time, which names the grant to put back. pg_locks is readable by
  # everyone unless an admin revoked it.
  defp held_keys(keys) do
    case Connection.query(@held_keys_statement, [keys]) do
      {:ok, %Postgrex.Result{rows: rows}} -> Enum.map(rows, fn [key] -> key end)
      {:error, %Postgrex.Error{postgres: %{code: :insufficient_privilege}}} -> []
      {:error, error} -> raise error
    end
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
  defp sweep_row(job_type, id), do: fail_abandoned(job_type, id, @cut_short_error)

  defp fail_abandoned(job_type, id, text) do
    {:ok, :ok} =
      Connection.transaction(fn ->
        with true <- run_lock_free?(lock_name(job_type, id)),
             %{status: :running, attempt: attempt} <-
               EntityOperations.get(job_type, id, lock: :no_key_update) do
          changes = attempt_failed_changes(job_type, attempt, text)

          :ok = EntityOperations.update(job_type, id, changes)
        else
          _held_or_not_running -> :ok
        end
      end)

    :ok
  end
end
