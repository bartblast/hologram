defmodule HologramSyncTests.Consistency.WriterTest do
  # async: false - each test truncates the shared tables.
  use HologramSyncTests.TestCase, async: false

  import HologramSyncTests.Helpers

  alias Hologram.DB
  alias Hologram.DB.Connection
  alias HologramSyncTests.Consistency.Checks
  alias HologramSyncTests.Consistency.Client
  alias HologramSyncTests.Consistency.History
  alias HologramSyncTests.Consistency.Writer
  alias HologramSyncTests.Entities.Card
  alias HologramSyncTests.Entities.Tag
  alias HologramSyncTests.Entities.User

  setup do
    truncate_tables()

    %{history: start_supervised!(History)}
  end

  # The first writer writes first and holds its transaction open until the second has committed -
  # and the first's state, read under the lock after that, holds both tags.
  test "orders overlapping transactions by their commits, not their starts", %{history: history} do
    test_pid = self()

    write_and_wait = fn ->
      create!(Tag, name: "first")
      send(test_pid, :first_wrote)

      receive do
        :release -> :ok
      end
    end

    first =
      Task.async(fn ->
        Writer.commit(history, :first, [{"create tag first", write_and_wait, 0}])
      end)

    assert_receive :first_wrote, 5_000

    assert {:committed, _second} = Writer.commit(history, :second, [create_tag("second", 0)])

    send(first.pid, :release)
    assert {:committed, _first} = Task.await(first)

    assert [%{writer: :second} = earlier, %{writer: :first} = later] = History.entries(history)
    assert tag_names(earlier.state) == ["second"]
    assert tag_names(later.state) == ["first", "second"]
    assert later.xid < earlier.xid
  end

  # The holder keeps the lock past reading its state, up to its commit, so the waiter's state, read
  # under the lock after it, holds the holder's tag.
  test "keeps a transaction waiting for the lock until the one holding it commits", %{
    history: history
  } do
    test_pid = self()

    # Held until PostgreSQL shows the waiter waiting on an advisory lock, so the waiter really
    # reached the lock while the holder had it.
    hold = fn ->
      send(test_pid, :holding)
      send(test_pid, {:waiter_seen, await_lock_waiter()})
    end

    holder =
      Task.async(fn ->
        Writer.commit(history, :holder, [create_tag("holder", 0)], before_commit: hold)
      end)

    assert_receive :holding, 5_000
    waiter = Task.async(fn -> Writer.commit(history, :waiter, [create_tag("waiter", 0)]) end)

    assert {:committed, holder_entry} = Task.await(holder, 10_000)
    assert {:committed, waiter_entry} = Task.await(waiter)

    assert_received {:waiter_seen, true}
    assert holder_entry.lock_order < waiter_entry.lock_order
    assert tag_names(holder_entry.state) == ["holder"]
    assert tag_names(waiter_entry.state) == ["holder", "waiter"]
  end

  test "frees the lock and leaves no state when a transaction rolls back holding it", %{
    history: history
  } do
    fail = fn -> raise "boom after the lock" end

    assert {:aborted, %{reason: "boom after the lock", stage: :commit}} =
             Writer.commit(history, :failing, [create_tag("rolled back", 0)], before_commit: fail)

    assert {:committed, entry} = Writer.commit(history, :next, [create_tag("next", 0)])

    assert History.entries(history) == [entry]
    assert tag_names(entry.state) == ["next"]
  end

  test "leaves no state for a transaction that rolled back", %{history: history} do
    ops = [create_tag("rolled back", 0), {"fail", fn -> raise "boom" end, 0}]

    assert {:aborted, %{reason: "boom", stage: :ops, writer: :failing}} =
             Writer.commit(history, :failing, ops)

    assert History.entries(history) == []
    assert [%{ops: ["create tag rolled back", "fail"]}] = History.aborted(history)
    assert DB.read(Tag) == []
  end

  # The client's times and the history's are one clock, and the frames' cursors and the history's
  # transaction ids one count, so a client syncing through real writes passes check 2.
  test "a client's records of real writes pass check 2", %{history: history} do
    assert {:committed, _seed} = Writer.commit(history, :seed, [{"fixture", &write_fixture/0, 0}])

    [member] = read_where(User, :name, "member")
    [card] = read_where(Card, :title, "open card")

    client = start_supervised!({Client, base_url: base_url(), user_id: member.id})
    Client.connect(client)
    assert Checks.await_converged(client, member.id, 5_000) == :ok

    rename = {"rename card", fn -> DB.update!(Card, card.id, title: "renamed") end, 0}
    assert {:committed, _renamed} = Writer.commit(history, :renamer, [rename])
    assert Checks.await_converged(client, member.id, 5_000) == :ok

    records = Client.records(client)

    assert Enum.any?(records, &(&1.cursor_tx != nil))
    assert Checks.leaks(records, History.entries(history), member.id) == []

    stale = %{List.last(records) | carried: %{"title" => "never written"}}
    assert [_leak] = Checks.leaks([stale], History.entries(history), member.id)
  end

  defp await_lock_waiter(attempts \\ 250) do
    {:ok, %{rows: [[waiting]]}} =
      Connection.query(
        """
        SELECT count(*) FROM pg_locks
        WHERE locktype = 'advisory' AND NOT granted AND objid = 1598 AND objsubid = 1
          AND database = (SELECT oid FROM pg_database WHERE datname = current_database())
        """,
        []
      )

    cond do
      waiting > 0 ->
        true

      attempts == 0 ->
        false

      true ->
        Process.sleep(20)
        await_lock_waiter(attempts - 1)
    end
  end

  defp create_tag(name, hold_ms) do
    {"create tag #{name}", fn -> create!(Tag, name: name) end, hold_ms}
  end

  defp read_where(type, field, value) do
    type
    |> DB.read()
    |> Enum.filter(&(Map.fetch!(&1, field) == value))
  end

  defp tag_names(state) do
    state.rows
    |> Map.fetch!(Tag)
    |> Map.values()
    |> Enum.map(& &1["name"])
    |> Enum.sort()
  end
end
