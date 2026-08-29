defmodule Hologram.Sync.FrameTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Sync.Frame

  alias Hologram.Entity
  alias Hologram.Entity.Metadata
  alias Hologram.Entity.Model
  alias Hologram.Sync.WireData
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3

  @cursor "g8uxAAAAZQ"

  describe "deltas/1" do
    defp news(overrides) do
      Map.merge(%{appeared: [], edges: [], patched: [], unsynced: []}, overrides)
    end

    test "sends a row that appeared whole" do
      row = Module2.new(a: true, c: "first")

      assert deltas(news(%{appeared: [row]})) == [
               %{
                 data: WireData.row(row),
                 id: row.id,
                 op: :put_entity,
                 type: "Hologram.Test.Fixtures.Entity.Module2"
               }
             ]
    end

    test "sends a row that changed as the attributes that moved" do
      row = %{
        Module2.new(a: true, c: "after")
        | __meta__: %Metadata{revisions: %{a: 1, c: 5}}
      }

      assert deltas(news(%{patched: [{row, %{c: "after"}}]})) == [
               %{
                 data: %{:c => "after", :"$revisions" => %{c: 5}},
                 id: row.id,
                 op: :patch_entity,
                 type: "Hologram.Test.Fixtures.Entity.Module2"
               }
             ]
    end

    test "carries the revisions of the columns a patch names" do
      row = %{
        Module2.new(a: true, c: "after")
        | __meta__: %Metadata{revisions: %{a: 1, c: 5}}
      }

      assert [%{data: data}] = deltas(news(%{patched: [{row, %{a: true, c: "after"}}]}))
      assert data[:"$revisions"] == %{a: 1, c: 5}
    end

    # The log stopped dropping server-only values, so a change to one reaches the frame - it is
    # gone from the data, and the revisions are taken against the data so that a client is never
    # told a column it may not have has moved.
    test "leaves a server-only attribute out of a patch's revisions" do
      row = %{
        Module14.new(email: "user@test.com")
        | __meta__: %Metadata{revisions: %{email: 3, password_hash: 4}}
      }

      moved = %{email: "user@test.com", password_hash: "hashed_secret_v5"}

      assert [%{data: data}] = deltas(news(%{patched: [{row, moved}]}))
      assert data[:"$revisions"] == %{email: 3}
      refute Map.has_key?(data, :password_hash)
    end

    # Every update moves the stamp, so a patch carrying a value that must be written for the wire
    # is the common case - and a DateTime handed over raw is one JSON refuses outright.
    test "sends the changed values written the way the wire carries them" do
      row = Module2.new(a: true, c: "after")
      moved = %{c: "after", updated_at: ~U[2026-08-16 16:20:00.000000Z]}

      assert [%{data: data}] = deltas(news(%{patched: [{row, moved}]}))

      assert data == %{
               :c => "after",
               :updated_at => "2026-08-16T16:20:00.000000Z",
               :"$revisions" => %{}
             }
    end

    test "sends a row that left as its id, under the type it was held under" do
      id = Entity.generate_id()

      assert deltas(news(%{unsynced: [{id, Module2}]})) == [
               %{id: id, op: :unsync_entity, type: "Hologram.Test.Fixtures.Entity.Module2"}
             ]
    end

    test "sends an edge as the pair it joined, under the type the edge itself names" do
      source_id = Entity.generate_id()
      target_id = Entity.generate_id()

      edge = %{
        entity_id: source_id,
        op: :add_relationship,
        relationship: "a",
        target_id: target_id,
        type: Module3
      }

      assert deltas(news(%{edges: [edge]})) == [
               %{
                 data: %{relationship: "a", target_id: target_id},
                 id: source_id,
                 op: :add_relationship,
                 type: "Hologram.Test.Fixtures.Entity.Module3"
               }
             ]
    end

    test "sends an edge as the pair it parted" do
      edge = %{
        entity_id: Entity.generate_id(),
        op: :del_relationship,
        relationship: "a",
        target_id: Entity.generate_id(),
        type: Module2
      }

      assert [%{op: :del_relationship}] = deltas(news(%{edges: [edge]}))
    end

    test "takes the type of an arrived row from the row itself" do
      row = Module14.new(email: "user@test.com")

      assert [%{type: "Hologram.Test.Fixtures.Entity.Module14"}] =
               deltas(news(%{appeared: [row]}))
    end

    test "sends nothing for news holding nothing" do
      assert deltas(news(%{})) == []
    end
  end

  describe "encode_deltas_envelope/4" do
    defp decoded_deltas(envelope) do
      "event: sync_deltas\nid: 42\ndata: " <> json = String.trim_trailing(envelope, "\n")

      Jason.decode!(json)["deltas"]
    end

    test "wraps the deltas in a sync_deltas SSE event envelope" do
      row = Module2.new(a: true, c: "first")

      payload = %{
        applied_seq: nil,
        cursor: @cursor,
        deltas: %{put_entity: %{"Hologram.Test.Fixtures.Entity.Module2" => [WireData.row(row)]}},
        model_hash: Model.hash(),
        protocol_version: 1
      }

      encoded = Jason.encode!(payload)

      assert encode_deltas_envelope(42, @cursor, [put_entity(row)], nil) ==
               "event: sync_deltas\nid: 42\ndata: #{encoded}\n\n"
    end

    # The op and the type are spelled once per group, and the row object alone is the delta - on
    # a fill, where a parent arrives with its include-reached children, every row travels exactly
    # once, flat, under its own type, with the to-many fact as the id list on the parent.
    test "groups an appearing parent and child by op and their own types" do
      child = Module2.new(a: true, c: "child")

      parent = Module3.new(c_id: Entity.generate_id())
      embedded_parent = %{parent | a: [child]}

      news = news(%{appeared: [embedded_parent, child]})
      envelope = encode_deltas_envelope(42, @cursor, deltas(news), nil)

      assert decoded_deltas(envelope) == %{
               "put_entity" => %{
                 "Hologram.Test.Fixtures.Entity.Module3" => [
                   %{
                     "$revisions" => %{},
                     "a" => [child.id],
                     "b_id" => nil,
                     "c_id" => parent.c_id,
                     "created_at" => nil,
                     "id" => parent.id,
                     "updated_at" => nil
                   }
                 ],
                 "Hologram.Test.Fixtures.Entity.Module2" => [
                   %{
                     "$revisions" => %{},
                     "a" => true,
                     "b" => nil,
                     "c" => "child",
                     "created_at" => nil,
                     "id" => child.id,
                     "updated_at" => nil
                   }
                 ]
               }
             }
    end

    test "groups every op of a mixed round, ids alone for the rows that left" do
      row = Module2.new(a: true, c: "after")
      gone_id = Entity.generate_id()
      target_id = Entity.generate_id()

      edge = %{
        entity_id: row.id,
        op: :add_relationship,
        relationship: "a",
        target_id: target_id,
        type: Module3
      }

      news =
        news(%{edges: [edge], patched: [{row, %{c: "after"}}], unsynced: [{gone_id, Module2}]})

      envelope = encode_deltas_envelope(42, @cursor, deltas(news), nil)

      assert decoded_deltas(envelope) == %{
               "patch_entity" => %{
                 "Hologram.Test.Fixtures.Entity.Module2" => [
                   %{"$revisions" => %{}, "c" => "after", "id" => row.id}
                 ]
               },
               "add_relationship" => %{
                 "Hologram.Test.Fixtures.Entity.Module3" => [
                   %{"id" => row.id, "relationship" => "a", "target_id" => target_id}
                 ]
               },
               "unsync_entity" => %{"Hologram.Test.Fixtures.Entity.Module2" => [gone_id]}
             }
    end

    test "stamps the model the values were read under" do
      envelope = encode_deltas_envelope(42, @cursor, [], nil)

      assert String.contains?(envelope, Model.hash())
    end

    test "stamps the protocol version the frame is spelled in" do
      envelope = encode_deltas_envelope(42, @cursor, [], nil)

      assert String.contains?(envelope, ~s["protocol_version":#{protocol_version()}])
    end

    test "carries the cursor the client hands back" do
      envelope = encode_deltas_envelope(42, @cursor, [], nil)

      assert String.contains?(envelope, ~s["cursor":"#{@cursor}"])
    end

    test "carries no cursor when there is nowhere to resume from" do
      envelope = encode_deltas_envelope(42, nil, [], nil)

      assert String.contains?(envelope, ~s["cursor":null])
    end

    test "carries how far the receiving replica's own batches are applied" do
      envelope = encode_deltas_envelope(42, @cursor, [], 7)

      assert String.contains?(envelope, ~s["applied_seq":7])
    end

    # Nil says nothing rather than nothing-applied, which is what a stream serving no replica has
    # to say - a client reading it as "none of mine have landed" would put its own writes back on
    # top of rows that already hold them.
    test "carries no number for a stream serving no replica" do
      envelope = encode_deltas_envelope(42, @cursor, [], nil)

      assert String.contains?(envelope, ~s["applied_seq":null])
    end

    test "never carries the value of a server-only attribute" do
      row = Module14.new(email: "user@test.com", password_hash: "hashed_secret_v3")

      envelope = encode_deltas_envelope(42, @cursor, [put_entity(row)], nil)

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
      row = Module2.new(a: true, c: "first")

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
