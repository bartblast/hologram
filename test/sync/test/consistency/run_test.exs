defmodule HologramSyncTests.Consistency.RunTest do
  # async: false - the test writes to the shared tables and reads the log.
  use HologramSyncTests.TestCase, async: false

  import HologramSyncTests.Helpers

  alias Hologram.DB.Connection
  alias Hologram.DB.Oplog
  alias Hologram.Sync.Catchup
  alias Hologram.Sync.Cursor
  alias HologramSyncTests.Consistency.Run
  alias HologramSyncTests.Entities.Tag

  @hash String.duplicate("0", 32)
  @schedule [:await_synced, :cut, :await_writers, :connect]

  setup do
    truncate_tables()
    :ok
  end

  # The client came back from far behind, then its stream ended and it reconnected on its own from
  # a fresh place: the return is what it was owed a start over for.
  test "judges a client's return by the first connect after its cut, not a later reconnect" do
    behind = Cursor.encode(Oplog.current_xmin(), 0, @hash, @hash)

    for index <- 0..Catchup.gap_limit(), do: create!(Tag, name: "tag #{index}")

    # Past every tag: a transaction id taken after they committed - the oldest one running can
    # still sit below them.
    {:ok, %{rows: [[next_xid]]}} = Connection.query("SELECT pg_current_xact_id()::text", [])

    caught_up =
      next_xid
      |> String.to_integer()
      |> Cursor.encode(0, @hash, @hash)

    events = [
      %{cursor: nil, kind: :connect},
      %{cause: :cut, kind: :closed},
      %{cursor: behind, kind: :connect},
      %{cause: :stream_end, kind: :closed},
      %{cursor: caught_up, kind: :connect}
    ]

    assert Run.missed_resync?(%{events: events, schedule: @schedule})

    resync = %{frame: "sync_resync", kind: :frame, reason: "gap_too_large"}
    told = List.insert_at(events, 3, resync)

    refute Run.missed_resync?(%{events: told, schedule: @schedule})
    # A start over told before the cut was owed to an earlier connection, and one told on a later
    # place than the return's to a client the return had already caught up.
    assert Run.missed_resync?(%{events: [resync | events], schedule: @schedule})
    assert Run.missed_resync?(%{events: List.insert_at(events, -1, resync), schedule: @schedule})
  end
end
