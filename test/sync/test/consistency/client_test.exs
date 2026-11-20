defmodule HologramSyncTests.Consistency.ClientTest do
  # async: false - each test truncates the shared tables.
  use HologramSyncTests.TestCase, async: false

  import HologramSyncTests.Helpers

  alias Hologram.DB
  alias Hologram.DB.QueryCache
  alias Hologram.Sync.Sessions
  alias HologramSyncTests.Consistency.Checks
  alias HologramSyncTests.Consistency.Client
  alias HologramSyncTests.Consistency.Model
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
    client = start_client(member.id, cut_when: &(types_markers(&1) == length(Model.types())))

    Client.connect(client)
    assert await(fn -> cut?(client) end)

    assert Client.cursor(client) == nil
    assert map_size(Client.store(client)[Space]) == 1

    [membership] =
      SpaceMember
      |> DB.read()
      |> Enum.filter(&(&1.user_id == member.id))

    DB.delete!(membership)

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

  # Stopped the way ExUnit stops it at a test's end, by its supervisor.
  test "a stopped client leaves no session on the server", %{users: [member | _users]} do
    client = start_supervised!({Client, base_url: base_url(), user_id: member.id}, id: :stopped)

    Client.connect(client)
    assert Checks.await_converged(client, member.id, 5_000) == :ok
    assert Sessions.list() != []

    stop_supervised!(:stopped)

    assert await(fn -> Sessions.list() == [] end)
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

  defp cut?(client) do
    client
    |> Client.events()
    |> Enum.any?(&(&1[:reason] == :cut))
  end

  defp start_client(user_id, opts \\ []) do
    start_supervised!({Client, [base_url: base_url(), user_id: user_id] ++ opts}, id: make_ref())
  end

  defp types_markers(events), do: Enum.count(events, &(&1[:scope] == "types"))
end
