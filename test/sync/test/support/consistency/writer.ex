defmodule HologramSyncTests.Consistency.Writer do
  @moduledoc false

  # Runs one writer transaction the way the randomized run writes: the operations through the
  # trusted write path, each followed by its hold, so transactions overlap and commit out of id
  # order - then, as its last statements, the commit lock, the transaction's id and the state it
  # leaves, read while no other writer can commit.
  #
  # The lock is held to the commit, and PostgreSQL takes a transaction out of the running set before
  # it lets its locks go, so the next writer to get the lock sees every earlier commit: commits
  # happen in lock order, and each state read under the lock is exactly the state its commit leaves.
  # It's taken with a plain query at the transaction's top level - `Hologram.DB.sql/3` runs in a
  # savepoint it rolls back, which would give the lock back at once (#1750).

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
  deadlock victim. Answers what it added.

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
        exception -> {:error, Exception.message(exception)}
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

      {:error, reason} ->
        aborted = %{ops: descriptions, reason: reason, writer: writer}
        :ok = History.put_aborted(history, aborted)

        {:aborted, aborted}
    end
  end

  defp run(ops, before_commit) do
    Enum.each(ops, fn {_description, fun, hold_ms} ->
      fun.()
      Process.sleep(hold_ms)
    end)

    {:ok, _result} = Connection.query("SELECT pg_advisory_xact_lock($1)", [@lock_key])
    after_lock_at = System.monotonic_time()
    # Strictly increasing across processes, unlike the monotonic time, which two reads can share.
    lock_order = System.unique_integer([:monotonic, :positive])

    {:ok, %{rows: [[xid]]}} = Connection.query("SELECT pg_current_xact_id()::text", [])
    state = Model.snapshot()

    before_commit.()

    %{
      after_lock_at: after_lock_at,
      lock_order: lock_order,
      state: state,
      xid: String.to_integer(xid)
    }
  end
end
