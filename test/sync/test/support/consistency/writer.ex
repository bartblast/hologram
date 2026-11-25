defmodule HologramSyncTests.Consistency.Writer do
  @moduledoc false

  # Runs one writer transaction the way the randomized run writes: the operations through the
  # trusted write path, each followed by its hold, so transactions overlap and commit out of the
  # order of their serials - then, as its last statements, the commit lock, the serials its log
  # entries hold and the state it leaves, read while no other writer can commit.
  #
  # The lock is held to the commit, and PostgreSQL takes a transaction out of the running set before
  # it lets its locks go, so the next writer to get the lock sees every earlier commit: commits
  # happen in lock order, and each state read under the lock is exactly the state its commit leaves.
  # It's taken with a plain query at the transaction's top level.

  alias Hologram.DB
  alias Hologram.DB.Connection
  alias HologramSyncTests.Consistency.History
  alias HologramSyncTests.Consistency.Model

  @lock_key 1_598

  @typedoc """
  An operation: what it does, in words for the trace, the function doing it, and how long to hold
  the transaction open after it, in milliseconds.
  """
  @type op :: {String.t(), (-> any), non_neg_integer}

  @doc """
  Runs the given operations in one transaction for the given writer, and adds it to the history as
  committed, or as aborted when an operation raised - a row a concurrent transaction deleted, or a
  deadlock victim - or something failed after them. Answers what it added. An aborted one names its
  `:stage`: `:ops` when an operation raised, the conflicts a run expects, and `:commit` when the
  lock, the state read or the commit failed, which a run doesn't.

  `:before_commit` runs once the state is read, with the commit lock held - for a test that holds a
  transaction there.
  """
  @spec commit(pid, term, list(op), keyword) :: {:committed, History.entry()} | {:aborted, map}
  def commit(history, writer, ops, opts \\ []) do
    before_commit = Keyword.get(opts, :before_commit, fn -> :ok end)
    descriptions = Enum.map(ops, &elem(&1, 0))

    result =
      try do
        DB.transaction(fn -> run(ops, before_commit) end)
      rescue
        exception -> {:error, {:commit, exception}}
      end

    case result do
      {:ok, entry} ->
        committed =
          Map.merge(entry, %{
            committed_at: System.monotonic_time(),
            ops: descriptions,
            writer: writer
          })

        :ok = History.put_committed(history, committed)

        {:committed, committed}

      {:error, failure} ->
        {stage, error} = staged(failure)

        aborted = %{
          error: error,
          ops: descriptions,
          reason: spell(error),
          stage: stage,
          writer: writer
        }

        :ok = History.put_aborted(history, aborted)

        {:aborted, aborted}
    end
  end

  # A failure the transaction itself rolled back with - a commit refused - is a failure after the
  # operations too.
  defp staged({:ops, _error} = failure), do: failure

  defp staged({:commit, _error} = failure), do: failure

  defp staged(reason), do: {:commit, reason}

  defp spell(exception) when is_exception(exception), do: Exception.message(exception)

  defp spell(reason), do: reason

  defp run(ops, before_commit) do
    Enum.each(ops, fn {_description, fun, hold_ms} ->
      try do
        fun.()
      rescue
        exception -> DB.rollback({:ops, exception})
      end

      Process.sleep(hold_ms)
    end)

    {:ok, _result} = Connection.query("SELECT pg_advisory_xact_lock($1)", [@lock_key])
    after_lock_at = System.monotonic_time()
    # Strictly increasing across processes, unlike the monotonic time, which two reads can share.
    lock_order = System.unique_integer([:monotonic, :positive])

    # A serial an operation spent without writing - an insert a conflict turned into nothing - is
    # left out, which only leaves the transaction's first serial higher than the one it took.
    {:ok, %{rows: [[min_seq, max_seq]]}} =
      Connection.query(
        ~s|SELECT min("seq"), max("seq") FROM "hologram_system"."oplog" | <>
          ~s|WHERE "tx" = pg_current_xact_id()|,
        []
      )

    state = Model.snapshot()

    before_commit.()

    %{
      after_lock_at: after_lock_at,
      lock_order: lock_order,
      max_seq: max_seq,
      min_seq: min_seq,
      state: state
    }
  end
end
