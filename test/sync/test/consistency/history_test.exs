defmodule HologramSyncTests.Consistency.HistoryTest do
  use ExUnit.Case, async: true

  alias HologramSyncTests.Consistency.History

  # Writers append once their transaction returns, so one that committed first can append second.
  test "lists committed transactions in the order they got the commit lock" do
    history = start_supervised!(History)

    # The last two read the same monotonic time, so only their place in lock order tells them apart.
    for {lock_order, writer} <- [{2, :second}, {1, :first}, {3, :third}] do
      entry = %{after_lock_at: min(lock_order, 2) * 10, lock_order: lock_order, writer: writer}

      :ok = History.put_committed(history, entry)
    end

    writers =
      history
      |> History.entries()
      |> Enum.map(& &1.writer)

    assert writers == [:first, :second, :third]
  end
end
