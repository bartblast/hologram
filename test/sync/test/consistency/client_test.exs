defmodule HologramSyncTests.Consistency.ClientTest do
  # async: false - each test truncates the shared tables.
  use HologramSyncTests.TestCase, async: false

  import HologramSyncTests.Helpers

  alias Hologram.Auth
  alias Hologram.DB
  alias Hologram.DB.QueryCache
  alias Hologram.Sync.Sessions
  alias HologramSyncTests.Consistency.Checks
  alias HologramSyncTests.Consistency.Client
  alias HologramSyncTests.Consistency.Model
  alias HologramSyncTests.Entities.Board
  alias HologramSyncTests.Entities.Card
  alias HologramSyncTests.Entities.Space
  alias HologramSyncTests.Entities.SpaceMember
  alias HologramSyncTests.Entities.Tag

  setup do
    truncate_tables()

    %{users: write_fixture()}
  end

  test "the build syncs every type the model holds" do
    assert QueryCache.synced_types() == Model.types()
  end

  test "a client filled from nothing holds what its user may read", %{users: users} do
    for user_id <- [nil | Enum.map(users, & &1.id)] do
      client = start_client(user_id)

      Client.connect(client)

      assert Checks.await_converged(client, user_id, 5_000) == :ok
      assert Client.failures(client) == []
    end
  end

  # Cut before the marker saying it holds everything, so it comes back with no place and refills.
  # The member loses its space meanwhile, so the rows of the space it holds have to be swept.
  test "a client cut off before its fill ends sweeps what it may no longer read", %{
    users: [member | _users]
  } do
    client = start_client(member.id)

    Client.connect(client, cut_when: &(types_markers(&1) == length(Model.types())))
    assert await(fn -> cut?(client) end)

    assert Client.cursor(client) == nil
    assert map_size(Client.store(client)[Space]) == 1

    delete_membership!(member)
    Client.connect(client)

    assert Checks.await_converged(client, member.id, 5_000) == :ok
    assert Client.store(client)[Space] == %{}
  end

  test "a connected client is told of a write", %{users: [member | _users]} do
    client = start_client(member.id)

    Client.connect(client)
    assert Checks.await_converged(client, member.id, 5_000) == :ok

    [card] =
      Card
      |> DB.read()
      |> Enum.filter(&(&1.title == "open card"))

    DB.update!(Card, card.id, title: "renamed card")

    assert Checks.await_converged(client, member.id, 5_000) == :ok
    assert get_in(Client.store(client), [Card, card.id, "title"]) == "renamed card"
  end

  test "a client passes over what arrives for a stream it cut", %{users: [member | _users]} do
    client = start_client(member.id)

    Client.connect(client)
    assert Checks.await_converged(client, member.id, 5_000) == :ok

    [%{request_id: cut_request_id}] =
      client
      |> Client.events()
      |> Enum.filter(&(&1.kind == :connect))

    Client.cut(client)
    Client.connect(client)
    assert Checks.await_converged(client, member.id, 5_000) == :ok

    stale_chunk = """
    event: sync_deltas
    data: {"cursor":null,"deltas":{"put_entity":{"HologramSyncTests.Entities.Tag":[{"id":"stale","name":"stale"}]}}}

    """

    send(client, {:http, {cut_request_id, :stream, stale_chunk}})

    refute Map.has_key?(Client.store(client)[Tag], "stale")
  end

  # Check 2 bounds a frame by its cursor's transaction id, so a cursor of another shape has to stop
  # the run rather than switch the bound off.
  test "a client fails on a cursor it can't read a transaction id from", %{
    users: [member | _users]
  } do
    client = start_client(member.id)

    Client.connect(client)
    assert Checks.await_converged(client, member.id, 5_000) == :ok

    [%{request_id: request_id}] =
      client
      |> Client.events()
      |> Enum.filter(&(&1.kind == :connect))

    chunk = """
    event: sync_deltas
    data: {"cursor":"123.0","deltas":{"put_entity":{"HologramSyncTests.Entities.Tag":[{"id":"t","name":"t"}]}}}

    """

    send(client, {:http, {request_id, :stream, chunk}})

    assert [%{cursor: "123.0", failure: "unreadable cursor"}] = Client.failures(client)
  end

  # Stopped the way ExUnit stops it at a test's end, by its supervisor.
  test "a stopped client leaves no session on the server", %{users: [member | _users]} do
    client = start_supervised!({Client, base_url: base_url(), user_id: member.id}, id: :stopped)

    Client.connect(client)
    assert Checks.await_converged(client, member.id, 5_000) == :ok
    assert Sessions.list() != []

    stop_supervised!(:stopped)

    assert await(fn -> Sessions.list() == [] end)
  end

  test "a client cut off once it holds everything comes back from its place", %{
    users: [member | _users]
  } do
    client = start_client(member.id)

    Client.connect(client)
    assert Checks.await_converged(client, member.id, 5_000) == :ok

    Client.cut(client)
    create!(Tag, name: "added while away")
    Client.connect(client)

    assert Checks.await_converged(client, member.id, 5_000) == :ok
    assert [nil, cursor] = connect_cursors(client)
    assert is_binary(cursor)
    assert resync_reasons(client) == []
    assert Client.failures(client) == []
  end

  # The session can't say whether the client holds the rows its user lost, so it names them by
  # hash.
  test "a client whose user left a space while it was away drops the space's rows", %{
    users: [member | _users]
  } do
    client = start_client(member.id)

    Client.connect(client)
    assert Checks.await_converged(client, member.id, 5_000) == :ok
    assert map_size(Client.store(client)[Card]) == 1

    Client.cut(client)
    delete_membership!(member)
    Client.connect(client)

    assert Checks.await_converged(client, member.id, 5_000) == :ok
    assert Client.store(client)[Card] == %{}
    assert {"unsync_hashed", wire_type(Card)} in received_ops(client)
    assert resync_reasons(client) == []
    assert Client.failures(client) == []
  end

  # The rows a type-wide grant hid can't be named, so the session names the ones the client may
  # keep: here the board the user still views through a grant on the row, and its card.
  test "a client whose user lost a type-wide grant while it was away keeps only what it may read",
       %{users: [_member, _viewer, wide_viewer, _outsider]} do
    [open_board] =
      Board
      |> DB.read()
      |> Enum.filter(&(&1.name == "open"))

    Auth.grant_role(wide_viewer, :viewer, open_board)

    client = start_client(wide_viewer.id)

    Client.connect(client)
    assert Checks.await_converged(client, wide_viewer.id, 5_000) == :ok
    assert map_size(Client.store(client)[Board]) == 3

    Client.cut(client)
    Auth.revoke_role(wide_viewer, :viewer, Board)
    Client.connect(client)

    assert Checks.await_converged(client, wide_viewer.id, 5_000) == :ok
    assert Map.keys(Client.store(client)[Board]) == [open_board.id]
    assert [%{"board_id" => board_id}] = Map.values(Client.store(client)[Card])
    assert board_id == open_board.id
    assert {"keep_hashed", wire_type(Board)} in received_ops(client)
    assert resync_reasons(client) == []
    assert Client.failures(client) == []
  end

  # Coming back from a place the server can't read starts over: the rows stay while the fill comes
  # again, and each type's marker sweeps the rows of the type it didn't send.
  test "a client told to start over keeps its rows until the fill says which to drop", %{
    users: [member | _users]
  } do
    client = start_client(member.id)

    Client.connect(client)
    assert Checks.await_converged(client, member.id, 5_000) == :ok

    Client.cut(client)
    Client.put_cursor(client, "unreadable")
    delete_membership!(member)
    Client.connect(client, cut_when: &match?([%{frame: "sync_resync"} | _events], &1))

    assert await(fn -> "cursor" in resync_reasons(client) and cut_count(client) == 2 end)
    assert map_size(Client.store(client)[Space]) == 1
    assert map_size(Client.store(client)[Tag]) == 2
    assert Client.cursor(client) == nil

    Client.connect(client)

    assert Checks.await_converged(client, member.id, 5_000) == :ok
    assert Client.store(client)[Space] == %{}
    assert map_size(Client.store(client)[Tag]) == 2
    assert Client.failures(client) == []
  end

  describe "Checks.diff/2" do
    test "names a missing row, an extra row, wrong fields and a wrong set" do
      expected = %{
        Card => %{
          "kept" => %{"board_id" => "b", "tags" => ["t1"], "title" => "kept"},
          "missing" => %{"board_id" => "b", "tags" => [], "title" => "missing"}
        }
      }

      store = %{
        Card => %{
          "extra" => %{"board_id" => "b", "tags" => [], "title" => "extra"},
          "kept" => %{"board_id" => "b", "tags" => ["t2"], "title" => "stale"}
        }
      }

      assert Checks.diff(store, expected) == [
               {:extra, Card, "extra", %{"board_id" => "b", "tags" => [], "title" => "extra"}},
               {:fields, Card, "kept", %{"board_id" => "b", "title" => "kept"},
                %{"board_id" => "b", "title" => "stale"}},
               {:set, Card, "kept", "tags", ["t1"], ["t2"]},
               {:missing, Card, "missing",
                %{"board_id" => "b", "tags" => [], "title" => "missing"}}
             ]
    end

    test "finds nothing when the store holds what's expected" do
      expected = %{Tag => %{"t1" => %{"cards" => [], "name" => "red"}}}

      assert Checks.diff(expected, expected) == []
    end
  end

  defp await(condition, attempts \\ 100) do
    cond do
      condition.() -> true
      attempts == 0 -> false
      true -> Process.sleep(50) && await(condition, attempts - 1)
    end
  end

  defp connect_cursors(client) do
    for %{kind: :connect, cursor: cursor} <- Client.events(client), do: cursor
  end

  defp cut_count(client) do
    client
    |> Client.events()
    |> Enum.count(&(&1[:cause] == :cut))
  end

  defp cut?(client) do
    client
    |> Client.events()
    |> Enum.any?(&(&1[:cause] == :cut))
  end

  defp delete_membership!(user) do
    [membership] =
      SpaceMember
      |> DB.read()
      |> Enum.filter(&(&1.user_id == user.id))

    DB.delete!(membership)
  end

  defp received_ops(client) do
    for %{kind: :frame, ops: ops} <- Client.events(client),
        {op, type, _count} <- ops,
        do: {op, type}
  end

  defp resync_reasons(client) do
    for %{frame: "sync_resync", reason: reason} <- Client.events(client), do: reason
  end

  defp start_client(user_id) do
    start_supervised!({Client, base_url: base_url(), user_id: user_id}, id: make_ref())
  end

  defp wire_type(type) do
    type
    |> Module.split()
    |> Enum.join(".")
  end

  defp types_markers(events), do: Enum.count(events, &(&1[:scope] == "types"))
end
