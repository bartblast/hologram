defmodule HologramSyncTests.Consistency.HistoryTest do
  use ExUnit.Case, async: true

  alias HologramSyncTests.Consistency.History

  # Writers append once their transaction returns, so one that committed first can append second.
  test "lists committed transactions in the order they got the commit lock" do
    history = start_supervised!(History)

    for {after_lock_at, writer} <- [{20, :second}, {10, :first}, {30, :third}] do
      :ok = History.put_committed(history, %{after_lock_at: after_lock_at, writer: writer})
    end

    writers =
      history
      |> History.entries()
      |> Enum.map(& &1.writer)

    assert writers == [:first, :second, :third]
  end
end
