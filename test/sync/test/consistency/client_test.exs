defmodule HologramSyncTests.Consistency.ClientTest do
  # async: false - each test truncates the shared tables.
  use HologramSyncTests.TestCase, async: false

  import Hologram.Query, only: [add_relationship: 3]
  import HologramSyncTests.Helpers

  alias Hologram.Auth
  alias Hologram.DB
  alias Hologram.DB.Oplog
  alias Hologram.DB.QueryCache
  alias Hologram.Sync.Cursor
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

  # Check 2 bounds a frame by its cursor's serial, so a cursor of another shape has to stop the run
  # rather than switch the bound off.
  test "a client fails on a cursor it can't read a serial from", %{
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

  test "a client fails on a marker's cursor it can't read", %{users: [member | _users]} do
    client = start_client(member.id)

    Client.connect(client)
    assert Checks.await_converged(client, member.id, 5_000) == :ok

    [%{request_id: request_id}] =
      client
      |> Client.events()
      |> Enum.filter(&(&1.kind == :connect))

    chunk = """
    event: synced
    data: {"cursor":"123.0","scope":"all"}

    """

    send(client, {:http, {request_id, :stream, chunk}})

    assert [%{cursor: "123.0", failure: "unreadable cursor"}] = Client.failures(client)
  end

  test "a client fails on a cursor it can't read on a frame with no rows", %{
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
    data: {"cursor":"123.0","deltas":{}}

    """

    send(client, {:http, {request_id, :stream, chunk}})

    assert [%{cursor: "123.0", failure: "unreadable cursor"}] = Client.failures(client)
  end

  test "a client records the rows a row's set and an added pair name", %{users: [member | _users]} do
    client = start_client(member.id)

    Client.connect(client)
    assert Checks.await_converged(client, member.id, 5_000) == :ok

    [%{request_id: request_id}] =
      client
      |> Client.events()
      |> Enum.filter(&(&1.kind == :connect))

    chunk = """
    event: sync_deltas
    data: {"cursor":null,"deltas":{"add_relationship":{"HologramSyncTests.Entities.Card":[{"id":"c","relationship":"tags","target_id":"t2"}]},"put_entity":{"HologramSyncTests.Entities.Tag":[{"cards":["c"],"id":"t","name":"t"}]}}}

    """

    send(client, {:http, {request_id, :stream, chunk}})

    named =
      client
      |> Client.records()
      |> Enum.take(-2)
      |> Enum.map(&{&1.type, &1.id, &1.named})

    assert named == [{Card, "c", [{Tag, "t2"}]}, {Tag, "t", [{Card, "c"}]}]
  end

  # Only a batch's last frame carries a place, and the batch's rows were read after every
  # transaction below the place the client already held.
  test "a client bounds a frame with no cursor by the place it held", %{users: [member | _users]} do
    client = start_client(member.id)

    Client.connect(client)
    assert Checks.await_converged(client, member.id, 5_000) == :ok

    {:ok, {seq, _tx, _at}, _log_id, _policy_hash, _types_hash} =
      client
      |> Client.cursor()
      |> Cursor.decode()

    [%{request_id: request_id}] =
      client
      |> Client.events()
      |> Enum.filter(&(&1.kind == :connect))

    chunk = """
    event: sync_deltas
    data: {"cursor":null,"deltas":{"put_entity":{"HologramSyncTests.Entities.Tag":[{"id":"t","name":"t"}]}}}

    """

    send(client, {:http, {request_id, :stream, chunk}})

    assert %{cursor_seq: ^seq, id: "t"} =
             client
             |> Client.records()
             |> List.last()
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

  # Once the type-wide grant is gone, the replay names the card only by the keep list.
  test "a client cut inside a batch drops a pair naming a row a grant had reached", %{
    users: [_member, _viewer, _wide_viewer, outsider]
  } do
    {client, red} =
      cut_with_pair_ahead_of_card(outsider, fn _board ->
        Auth.grant_role(outsider, :viewer, Board)
      end)

    Auth.revoke_role(outsider, :viewer, Board)
    Client.connect(client)

    assert Checks.await_converged(client, outsider.id, 5_000) == :ok
    assert Client.store(client)[Tag][red.id]["cards"] == []
    assert {"keep_hashed", wire_type(Card)} in received_ops(client)
    assert resync_reasons(client) == []
    assert Client.failures(client) == []
  end

  # Once the membership is gone, the replay names the card only by its hash.
  test "a client cut inside a batch drops a pair naming a row a membership had reached", %{
    users: [_member, _viewer, _wide_viewer, outsider]
  } do
    {client, red} =
      cut_with_pair_ahead_of_card(outsider, fn board ->
        create!(SpaceMember, space_id: board.space_id, user_id: outsider.id)
      end)

    delete_membership!(outsider)
    Client.connect(client)

    assert Checks.await_converged(client, outsider.id, 5_000) == :ok
    assert Client.store(client)[Tag][red.id]["cards"] == []
    assert {"unsync_hashed", wire_type(Card)} in received_ops(client)
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

  # The numbers come above anything the sequence gave, so no limit the server tells reaches them.
  test "a client holds back a number above its final limit until a limit reaches it", %{
    users: [member | _users]
  } do
    client = start_client(member.id)

    Client.connect(client)
    assert Checks.await_converged(client, member.id, 5_000) == :ok
    assert await(fn -> Client.final_seq(client) != nil end)

    request_id = request_id(client)
    above = 1_000_000_000_000

    send_frame(client, request_id, "sync_deltas", %{
      cursor: nil,
      deltas: %{
        put_entity: %{
          "HologramSyncTests.Entities.Tag" => [
            %{id: "t", name: "t", server_created_seq: above, server_updated_seq: above}
          ]
        }
      }
    })

    assert shown_numbers(client, "t") == {nil, nil}

    send_frame(client, request_id, "sync_deltas", %{
      cursor: nil,
      deltas: %{
        patch_entity: %{
          "HologramSyncTests.Entities.Tag" => [
            %{id: "t", name: "u", server_updated_seq: above + 1}
          ]
        }
      },
      final_seq: above
    })

    # The patch's number took the put's place beside the row, as a later save's does.
    assert shown_numbers(client, "t") == {above, nil}
    assert Client.final_seq(client) == above

    send_frame(client, request_id, "sync_deltas", %{
      cursor: nil,
      deltas: %{},
      final_seq: above + 1
    })

    assert shown_numbers(client, "t") == {above, above + 1}
  end

  # A fill's marker makes the fill's limit only its own type's: the rows of a type still to come
  # arrive in no number order, so one at or below the limit can still follow.
  test "a client mid-fill holds back a type's numbers until that type's marker", %{
    users: [member | _users]
  } do
    client = start_client(member.id)

    Client.connect(client)
    assert Checks.await_converged(client, member.id, 5_000) == :ok
    assert await(fn -> Client.final_seq(client) != nil end)

    request_id = request_id(client)
    kept = Client.final_seq(client)
    above = 1_000_000_000_000

    marker = fn type ->
      %{cursor: nil, final_seq: above, scope: "types", types: [wire_type(type)]}
    end

    send_frame(client, request_id, "sync_resync", %{reason: "gap_too_large"})
    send_frame(client, request_id, "synced", marker.(Space))

    send_frame(client, request_id, "sync_deltas", %{
      cursor: nil,
      deltas: %{
        put_entity: %{
          wire_type(Tag) => [
            %{id: "t", name: "t", server_created_seq: above, server_updated_seq: above}
          ]
        }
      }
    })

    assert shown_numbers(client, "t") == {nil, nil}
    assert last_view(client).finals[Space] == above
    assert last_view(client).finals[Tag] == kept

    send_frame(client, request_id, "synced", marker.(Tag))

    assert shown_numbers(client, "t") == {above, above}
    assert last_view(client).finals[Tag] == above

    # The next fill takes the marker's limit, but not the numbers it filed.
    send_frame(client, request_id, "sync_resync", %{reason: "gap_too_large"})
    send_frame(client, request_id, "sync_deltas", %{cursor: nil, deltas: %{}})

    assert shown_numbers(client, "t") == {above, above}
    assert last_view(client).finals[Tag] == kept
    assert last_view(client).proven[Tag] == above
  end

  # The numbers came from a log that's gone, so none of them orders anything against the new one's.
  test "a client told its log is gone forgets the final limit and every number", %{
    users: [member | _users]
  } do
    client = start_client(member.id)

    Client.connect(client)
    assert Checks.await_converged(client, member.id, 5_000) == :ok
    assert await(fn -> Client.final_seq(client) != nil end)

    # A limit below the fixture's tags leaves them unnumbered until it reaches them.
    assert await(fn -> {nil, nil} not in shown_tags(client) end)

    send_frame(client, request_id(client), "sync_resync", %{reason: "retention"})

    assert Client.final_seq(client) == nil
    forgotten = shown_tags(client)

    assert Enum.uniq(forgotten) == [{nil, nil}]
  end

  # A reload starts from what the store wrote down, so the page comes back from its place and keeps
  # its numbers and the final limit written with that place.
  test "a client reloading comes back from its place with its numbers", %{
    users: [member | _users]
  } do
    client = start_client(member.id)

    Client.connect(client)
    assert Checks.await_converged(client, member.id, 5_000) == :ok
    assert await(fn -> Client.final_seq(client) != nil end)

    Client.cut(client)

    # The place and the limit written down with it, which a frame naming no place can have left
    # below the one the page shows.
    %{cursor: cursor, stored_final: stored_final} = :sys.get_state(client)
    shown = last_view(client)

    create!(Tag, name: "while away")
    Client.reload(client)

    assert Checks.await_converged(client, member.id, 5_000) == :ok
    cursors = connect_cursors(client)

    assert List.last(cursors) == cursor
    events = Client.events(client)

    assert Enum.any?(
             events,
             &(&1.kind == :reload and &1.from == :store and &1.final_seq == stored_final)
           )

    # A number above the stored limit waits again after the reload, so only rows at or below it
    # come back as shown.
    kept =
      for {id, {created_seq, updated_seq} = numbers} <- shown.rows[Tag],
          Enum.all?([created_seq, updated_seq], &(&1 == nil or &1 <= stored_final)),
          into: %{},
          do: {id, numbers}

    after_reload = last_view(client)

    assert Map.take(after_reload.rows[Tag], Map.keys(kept)) == kept
    assert Client.failures(client) == []
  end

  # The browser refuses a store with no place and clears it, so the page fills from nothing and
  # holds no final limit until the server names one.
  test "a client reloading with no place written down fills from nothing", %{
    users: [member | _users]
  } do
    client = start_client(member.id)

    Client.connect(client)
    assert Checks.await_converged(client, member.id, 5_000) == :ok

    Client.cut(client)
    Client.put_cursor(client, nil)
    Client.reload(client)

    events = Client.events(client)

    assert Enum.any?(events, &(&1.kind == :reload and &1.from == :nothing))
    cursors = connect_cursors(client)

    assert List.last(cursors) == nil
    assert Checks.await_converged(client, member.id, 5_000) == :ok
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

  # The run reads a client's return as the first connect after its cut, so a cut that takes back a
  # pending reconnect has to show.
  test "a cut while a client waits to reconnect is recorded and keeps it away", %{
    users: [member | _users]
  } do
    client = start_client(member.id)

    Client.connect(client)
    assert Checks.await_converged(client, member.id, 5_000) == :ok

    [%{request_id: request_id}] =
      client
      |> Client.events()
      |> Enum.filter(&(&1.kind == :connect))

    send(client, {:http, {request_id, :stream_end, []}})
    Client.cut(client)

    Process.sleep(500)

    assert [:connect, :stream_end, :cut] =
             client
             |> Client.events()
             |> Enum.filter(&(&1.kind in [:connect, :closed]))
             |> Enum.map(&(&1[:cause] || &1.kind))
  end

  defp request_id(client) do
    client
    |> Client.events()
    |> Enum.filter(&(&1.kind == :connect))
    |> List.last()
    |> Map.fetch!(:request_id)
  end

  defp send_frame(client, request_id, event, data) do
    send(
      client,
      {:http, {request_id, :stream, "event: #{event}\ndata: #{Jason.encode!(data)}\n\n"}}
    )
  end

  defp shown_numbers(client, id) do
    last_view(client).rows[Tag][id]
  end

  defp last_view(client) do
    client
    |> Client.views()
    |> List.last()
  end

  # Every tag's numbers as the client holds them, read from its state: a client with no final limit
  # keeps no view.
  defp shown_tags(client) do
    client
    |> :sys.get_state()
    |> Map.fetch!(:tables)
    |> Map.fetch!("HologramSyncTests.Entities.Tag")
    |> Enum.map(fn {_id, row} -> {row["server_created_seq"], row["server_updated_seq"]} end)
  end

  defp connect_cursors(client) do
    for %{kind: :connect, cursor: cursor} <- Client.events(client), do: cursor
  end

  # A client holding a tag, cut right after the catch-up's first frame of cards, which carries the
  # pair under the tag naming a card a later frame holds. The given function gives the user access
  # to the board's cards while the client is away.
  defp cut_with_pair_ahead_of_card(user, give_access) do
    [red] =
      Tag
      |> DB.read()
      |> Enum.filter(&(&1.name == "red"))

    [other_board] =
      Board
      |> DB.read()
      |> Enum.filter(&(&1.name == "other"))

    for number <- 1..6, do: create!(Card, board_id: other_board.id, title: "filler #{number}")

    tagged = create!(Card, board_id: other_board.id, title: "tagged")

    tagged
    |> add_relationship(:tags, red.id)
    |> DB.update!()

    # A save left running elsewhere would hold the client's place below these writes, and the
    # catch-up would then replay them and restate the tag's set.
    edge = Oplog.last_serial()
    assert await(fn -> read_seq() >= edge end)

    client = start_client(user.id)

    Client.connect(client)
    assert Checks.await_converged(client, user.id, 5_000) == :ok

    {:ok, {seq, _tx, _at}, _log_id, _policy_hash, _types_hash} =
      client
      |> Client.cursor()
      |> Cursor.decode()

    assert seq >= edge

    Client.cut(client)
    give_access.(other_board)
    Client.connect(client, cut_when: &pair_frame?/1)

    assert await(fn -> cut_count(client) == 2 end)

    store = Client.store(client)

    assert tagged.id in store[Tag][red.id]["cards"]
    refute Map.has_key?(store[Card], tagged.id)

    {client, red}
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

  defp pair_frame?([%{frame: "sync_deltas", ops: ops} | _events]) do
    Enum.any?(ops, &match?({"add_relationship", _type, _count}, &1))
  end

  defp pair_frame?(_events), do: false

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
