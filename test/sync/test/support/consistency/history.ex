defmodule HologramSyncTests.Consistency.History do
  @moduledoc false

  # Every state the writers' transactions left, in commit order, and the transactions that rolled
  # back - what check 2 picks the states a frame could have been read from out of.
  #
  # Writers append once their transaction has returned, so two can arrive in either order. Commit
  # order is lock order, and each entry's `lock_order` is taken while its transaction holds the lock
  # every writer takes last, so sorting by it gives commit order - `after_lock_at` too, save that two
  # monotonic time reads can be equal.

  use Agent

  @typedoc """
  A committed transaction: when it got the commit lock and when it had committed, as
  `System.monotonic_time/0` in native units, its place in lock order, the first and last serials
  its log entries hold (nil for a transaction that logged nothing), the writer and the operations
  it ran, and the state of the tables it left (see `HologramSyncTests.Consistency.Model.snapshot/0`).
  """
  @type entry :: %{
          after_lock_at: integer,
          committed_at: integer,
          lock_order: integer,
          max_seq: pos_integer | nil,
          min_seq: pos_integer | nil,
          ops: list(String.t()),
          state: map,
          writer: term
        }

  @doc """
  Starts an empty history.
  """
  @spec start_link(keyword) :: Agent.on_start()
  def start_link(_opts \\ []) do
    Agent.start_link(fn -> %{aborted: [], committed: []} end)
  end

  @doc """
  Returns the transactions that rolled back, each with its writer, operations and reason, oldest
  first.
  """
  @spec aborted(pid) :: list(map)
  def aborted(history) do
    Agent.get(history, &Enum.reverse(&1.aborted))
  end

  @doc """
  Returns the committed transactions in commit order.
  """
  @spec entries(pid) :: list(entry)
  def entries(history) do
    Agent.get(history, &Enum.sort_by(&1.committed, fn entry -> entry.lock_order end))
  end

  @doc """
  Adds a transaction that rolled back.
  """
  @spec put_aborted(pid, map) :: :ok
  def put_aborted(history, aborted) do
    Agent.update(history, &%{&1 | aborted: [aborted | &1.aborted]})
  end

  @doc """
  Adds a committed transaction.
  """
  @spec put_committed(pid, entry) :: :ok
  def put_committed(history, entry) do
    Agent.update(history, &%{&1 | committed: [entry | &1.committed]})
  end
end
