defmodule Hologram.Sync.FrameTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Sync.Frame

  alias Hologram.Entity
  alias Hologram.Entity.Model
  alias Hologram.Sync.WireData
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2

  @cursor "g8uxAAAAZQ"

  describe "deltas/2" do
    defp news(overrides) do
      Map.merge(%{appeared: [], edges: [], patched: [], unsynced: []}, overrides)
    end

    test "sends a row that appeared whole" do
      row = Entity.new(Module2, a: true, c: "first")

      assert deltas(news(%{appeared: [row]}), Module2) == [
               %{
                 data: WireData.row(row),
                 id: row.id,
                 op: :put_entity,
                 type: "Hologram.Test.Fixtures.Entity.Module2"
               }
             ]
    end

    test "sends a row that changed as the attributes that moved" do
      row = Entity.new(Module2, a: true, c: "after")

      assert deltas(news(%{patched: [{row, %{c: "after"}}]}), Module2) == [
               %{
                 data: %{c: "after"},
                 id: row.id,
                 op: :patch_entity,
                 type: "Hologram.Test.Fixtures.Entity.Module2"
               }
             ]
    end

    # Every update moves the stamp, so a patch carrying a value that must be written for the wire
    # is the common case - and a DateTime handed over raw is one JSON refuses outright.
    test "sends the changed values written the way the wire carries them" do
      row = Entity.new(Module2, a: true, c: "after")
      moved = %{c: "after", updated_at: ~U[2026-08-16 16:20:00.000000Z]}

      assert [%{data: data}] = deltas(news(%{patched: [{row, moved}]}), Module2)
      assert data == %{c: "after", updated_at: "2026-08-16T16:20:00.000000Z"}
    end

    test "sends a row that left as its id, under the window's type" do
      id = Entity.generate_id()

      assert deltas(news(%{unsynced: [id]}), Module2) == [
               %{id: id, op: :unsync_entity, type: "Hologram.Test.Fixtures.Entity.Module2"}
             ]
    end

    test "sends an edge as the pair it joined" do
      source_id = Entity.generate_id()
      target_id = Entity.generate_id()

      edge = %{
        entity_id: source_id,
        op: :add_relationship,
        relationship: "a",
        target_id: target_id
      }

      assert deltas(news(%{edges: [edge]}), Module2) == [
               %{
                 data: %{relationship: "a", target_id: target_id},
                 id: source_id,
                 op: :add_relationship,
                 type: "Hologram.Test.Fixtures.Entity.Module2"
               }
             ]
    end

    test "sends an edge as the pair it parted" do
      edge = %{
        entity_id: Entity.generate_id(),
        op: :del_relationship,
        relationship: "a",
        target_id: Entity.generate_id()
      }

      assert [%{op: :del_relationship}] = deltas(news(%{edges: [edge]}), Module2)
    end

    test "takes the type of an arrived row from the row rather than from the window" do
      row = Entity.new(Module14, email: "user@test.com")

      assert [%{type: "Hologram.Test.Fixtures.Entity.Module14"}] =
               deltas(news(%{appeared: [row]}), Module2)
    end

    test "sends nothing for news holding nothing" do
      assert deltas(news(%{}), Module2) == []
    end
  end

  describe "encode_deltas_envelope/3" do
    test "wraps the deltas in a sync_deltas SSE event envelope" do
      row = Entity.new(Module2, a: true, c: "first")
      deltas = [put_entity(row)]

      payload = %{
        cursor: @cursor,
        deltas: deltas,
        model_hash: Model.hash(),
        protocol_version: 1
      }

      encoded = Jason.encode!(payload)

      assert encode_deltas_envelope(42, @cursor, deltas) ==
               "event: sync_deltas\nid: 42\ndata: #{encoded}\n\n"
    end

    test "stamps the model the values were read under" do
      envelope = encode_deltas_envelope(42, @cursor, [])

      assert String.contains?(envelope, Model.hash())
    end

    test "stamps the protocol version the frame is spelled in" do
      envelope = encode_deltas_envelope(42, @cursor, [])

      assert String.contains?(envelope, ~s["protocol_version":#{protocol_version()}])
    end

    test "carries the cursor the client hands back" do
      envelope = encode_deltas_envelope(42, @cursor, [])

      assert String.contains?(envelope, ~s["cursor":"#{@cursor}"])
    end

    test "carries no cursor when there is nowhere to resume from" do
      envelope = encode_deltas_envelope(42, nil, [])

      assert String.contains?(envelope, ~s["cursor":null])
    end

    test "never carries the value of a server-only attribute" do
      row = Entity.new(Module14, email: "user@test.com", password_hash: "hashed_secret_v3")

      envelope = encode_deltas_envelope(42, @cursor, [put_entity(row)])

      assert String.contains?(envelope, ~s["email":"user@test.com"])

      # Under JSON the KEY goes too, not only the value - which is the whole of what the client is
      # told about an attribute it may not have.
      refute String.contains?(envelope, "hashed_secret_v3")
      refute String.contains?(envelope, "password_hash")
    end
  end

  describe "encode_reload_envelope/2" do
    test "wraps the notice in a sync_reload SSE event envelope" do
      payload = %{protocol_version: 1, reason: :model_hash}
      encoded = Jason.encode!(payload)

      assert encode_reload_envelope(42, :model_hash) ==
               "event: sync_reload\nid: 42\ndata: #{encoded}\n\n"
    end

    # A notice that its bundle is stale and an order to drop what it holds are different things,
    # and a client told the wrong one either reloads for nothing or throws away rows it still has.
    test "is a kind of its own, not the one that says to start over" do
      envelope = encode_reload_envelope(42, :model_hash)

      refute String.contains?(envelope, "sync_resync")
    end
  end

  describe "encode_resync_envelope/2" do
    test "wraps the discard marker in a sync_resync SSE event envelope" do
      payload = %{protocol_version: 1, reason: :retention}
      encoded = Jason.encode!(payload)

      assert encode_resync_envelope(42, :retention) ==
               "event: sync_resync\nid: 42\ndata: #{encoded}\n\n"
    end

    test "says which door the client came through" do
      envelope = encode_resync_envelope(42, :model_hash)

      assert String.contains?(envelope, ~s["reason":"model_hash"])
    end
  end

  describe "encode_synced_envelope/2" do
    test "wraps the completeness marker in a synced SSE event envelope" do
      payload = %{protocol_version: 1, scope: :page}
      encoded = Jason.encode!(payload)

      assert encode_synced_envelope(42, :page) == "event: synced\nid: 42\ndata: #{encoded}\n\n"
    end

    test "says which queries the client may now answer itself" do
      payload = %{protocol_version: 1, scope: :all}
      encoded = Jason.encode!(payload)

      assert encode_synced_envelope(42, :all) == "event: synced\nid: 42\ndata: #{encoded}\n\n"
    end
  end

  describe "protocol_version/0" do
    test "returns the version this build speaks" do
      assert protocol_version() == 1
    end
  end

  describe "put_entity/1" do
    test "hands over the whole row, under the type the row itself names" do
      row = Entity.new(Module2, a: true, c: "first")

      assert put_entity(row) == %{
               data: WireData.row(row),
               id: row.id,
               op: :put_entity,
               type: "Hologram.Test.Fixtures.Entity.Module2"
             }
    end
  end

  describe "unsync_entity/2" do
    test "names a row that left by its id, under the type given for it" do
      id = Entity.generate_id()

      assert unsync_entity(id, Module2) == %{
               id: id,
               op: :unsync_entity,
               type: "Hologram.Test.Fixtures.Entity.Module2"
             }
    end
  end
end
