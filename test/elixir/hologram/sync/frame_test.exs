defmodule Hologram.Sync.FrameTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Sync.Frame
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Entity
  alias Hologram.Entity.Metadata
  alias Hologram.Entity.Model
  alias Hologram.Policy
  alias Hologram.Sync.WireData
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3

  @cursor "g8uxAAAAZQ"

  use_module_stub :query_cache

  # A task may be deleted while its board holds no card by the user - read through the task's
  # board, so a task with no board has an empty set, answered without reading the database: yes for
  # a user, and no for a visitor, since the rule asks about the actor.
  defmodule VerdictBoard do
    use Hologram.Entity

    relationship :cards, [__MODULE__.Card], inverse: board

    allow :read

    defmodule Card do
      use Hologram.Entity

      relationship :author, Hologram.Test.Fixtures.Entity.Module14, optional: true
      relationship :board, Hologram.Sync.FrameTest.VerdictBoard, optional: true

      allow :read
    end
  end

  defmodule VerdictTask do
    use Hologram.Entity

    relationship :board, VerdictBoard, optional: true

    allow :read
    allow :delete, when: none(card <- board.cards, card.author_id == user_id())
  end

  defp delete_key do
    Policy.verdict_key(
      VerdictTask,
      :delete,
      {:none, {[:board, :cards], [{:author_id, :==, {:actor}}]}}
    )
  end

  # A build with a page checking permissions on the client - the only kind whose rows carry
  # verdicts.
  defp check_permissions do
    stub_with(QueryCacheMock, QueryCacheStub)
    :persistent_term.put(QueryCacheStub.persistent_term_key(), %{permission_checking?: true})

    on_exit(fn -> :persistent_term.erase(QueryCacheStub.persistent_term_key()) end)
  end

  describe "deltas/3" do
    defp news(overrides) do
      Map.merge(%{appeared: [], edges: [], patched: [], unsynced: []}, overrides)
    end

    test "sends a patch with the verdicts that moved beside the values" do
      row = %{
        Module2.new(a: true, c: "after")
        | __meta__: %Metadata{revisions: %{a: 1, c: 5}}
      }

      assert [%{data: data, op: :patch_entity}] =
               deltas(news(%{patched: [{row, %{c: "after"}, %{"delete:abc" => false}}]}), nil)

      assert data == %{
               "$revisions": %{c: 5},
               "$verdicts": %{"delete:abc" => false},
               c: "after"
             }
    end

    test "names the rows a client may hold that no longer reach it by their hashes" do
      id = Entity.generate_id()

      assert deltas(news(%{hidden: [{Module2, "q3Vx", [id]}]}), nil) == [
               unsync_hashed(Module2, "q3Vx", [id])
             ]
    end

    test "sends a patch naming no value for a row whose verdicts alone moved" do
      row = Module2.new(a: true, c: "after")

      assert deltas(news(%{patched: [{row, %{}, %{"delete:abc" => false}}]}), nil) == [
               %{
                 data: %{"$revisions": %{}, "$verdicts": %{"delete:abc" => false}},
                 id: row.id,
                 op: :patch_entity,
                 type: "Hologram.Test.Fixtures.Entity.Module2"
               }
             ]
    end

    test "sends a row that appeared with the user's verdicts" do
      check_permissions()

      row = VerdictTask.new()

      assert [%{data: %{"$verdicts": verdicts}, op: :put_entity}] =
               deltas(news(%{appeared: [row]}), Entity.generate_id())

      assert verdicts == %{delete_key() => true}
    end

    test "sends a row that appeared with the verdicts given for it" do
      check_permissions()

      row = VerdictTask.new()
      given = %{VerdictTask => %{row.id => %{delete_key() => false}}}

      assert [%{data: %{"$verdicts": verdicts}, op: :put_entity}] =
               deltas(news(%{appeared: [row]}), Entity.generate_id(), given)

      assert verdicts == %{delete_key() => false}
    end

    test "works out the verdicts of a row that appeared with none given for it" do
      check_permissions()

      row = VerdictTask.new()
      given = %{VerdictTask => %{Entity.generate_id() => %{delete_key() => false}}}

      assert [%{data: %{"$verdicts": verdicts}, op: :put_entity}] =
               deltas(news(%{appeared: [row]}), Entity.generate_id(), given)

      assert verdicts == %{delete_key() => true}
    end

    test "works out the verdicts of a row that appeared with some given for its id under another type" do
      check_permissions()

      row = VerdictTask.new()
      given = %{VerdictBoard => %{row.id => %{delete_key() => false}}}

      assert [%{data: %{"$verdicts": verdicts}, op: :put_entity}] =
               deltas(news(%{appeared: [row]}), Entity.generate_id(), given)

      assert verdicts == %{delete_key() => true}
    end

    test "sends a row that appeared whole" do
      row = Module2.new(a: true, c: "first")

      assert deltas(news(%{appeared: [row]}), nil) == [
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

      assert deltas(news(%{patched: [{row, %{c: "after"}, nil}]}), nil) == [
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

      assert [%{data: data}] = deltas(news(%{patched: [{row, %{a: true, c: "after"}, nil}]}), nil)
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

      assert [%{data: data}] = deltas(news(%{patched: [{row, moved, nil}]}), nil)
      assert data[:"$revisions"] == %{email: 3}
      refute Map.has_key?(data, :password_hash)
    end

    # Every update moves the stamp, so a patch carrying a value that must be written for the wire
    # is the common case - and a DateTime handed over raw is one JSON refuses outright.
    test "sends the changed values written the way the wire carries them" do
      row = Module2.new(a: true, c: "after")
      moved = %{c: "after", updated_at: ~U[2026-08-16 16:20:00.000000Z]}

      assert [%{data: data}] = deltas(news(%{patched: [{row, moved, nil}]}), nil)

      assert data == %{
               :c => "after",
               :updated_at => "2026-08-16T16:20:00.000000Z",
               :"$revisions" => %{}
             }
    end

    test "sends a row that left as its id, under the type it was held under" do
      id = Entity.generate_id()

      assert deltas(news(%{unsynced: [{id, Module2}]}), nil) == [
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

      assert deltas(news(%{edges: [edge]}), nil) == [
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

      assert [%{op: :del_relationship}] = deltas(news(%{edges: [edge]}), nil)
    end

    test "takes the type of an arrived row from the row itself" do
      row = Module14.new(email: "user@test.com")

      assert [%{type: "Hologram.Test.Fixtures.Entity.Module14"}] =
               deltas(news(%{appeared: [row]}), nil)
    end

    test "sends nothing for news holding nothing" do
      assert deltas(news(%{}), nil) == []
    end
  end

  # The same vectors test/javascript/drop_hash_test.mjs checks the browser's hash against.
  describe "drop_hash/2" do
    test "hashes a salt and an id the way the browser does" do
      assert drop_hash("salt", "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e0f") == "112df949ed165eb9"
    end

    test "hashes nothing at all as SHA-256 does" do
      assert drop_hash("", "") == "e3b0c44298fc1c14"
    end

    test "hashes a short message as SHA-256 does" do
      assert drop_hash("a", "b") == "fb8e20fc2e4c3f24"
    end

    test "hashes a message longer than one block" do
      assert drop_hash(String.duplicate("x", 40), String.duplicate("y", 40)) == "5f23e845240fffa4"
    end

    test "hashes the same id differently under another salt" do
      id = Entity.generate_id()

      refute drop_hash("salt", id) == drop_hash("other", id)
    end
  end

  describe "drop_salt/0" do
    test "answers 16 random bytes in url-safe base64" do
      salt = drop_salt()

      assert {:ok, bytes} = Base.url_decode64(salt, padding: false)
      assert byte_size(bytes) == 16
    end

    test "answers a fresh salt each time" do
      refute drop_salt() == drop_salt()
    end
  end

  describe "encode_deltas_envelope/4" do
    test "spells a put's verdicts as a $verdicts object beside the row's values" do
      row = Module2.new(a: true, c: "first")

      envelope =
        encode_deltas_envelope(42, @cursor, [put_entity(row, %{"delete:abc" => true})], nil)

      [_event, _id, "data: " <> json, _blank, _end] = String.split(envelope, "\n")

      %{"deltas" => %{"put_entity" => %{"Hologram.Test.Fixtures.Entity.Module2" => [data]}}} =
        Jason.decode!(json)

      assert data["$verdicts"] == %{"delete:abc" => true}
    end

    defp decoded_deltas(envelope) do
      "event: sync_deltas\nid: 42\ndata: " <> json = String.trim_trailing(envelope, "\n")

      Jason.decode!(json)["deltas"]
    end

    test "carries a hashed drop as its salt and hashes, under its type" do
      id = Entity.generate_id()

      envelope = encode_deltas_envelope(42, @cursor, [unsync_hashed(Module2, "q3Vx", [id])], nil)

      assert decoded_deltas(envelope) == %{
               "unsync_hashed" => %{
                 "Hologram.Test.Fixtures.Entity.Module2" => [
                   %{"hashes" => [drop_hash("q3Vx", id)], "salt" => "q3Vx"}
                 ]
               }
             }
    end

    test "carries a keep list as its salt and hashes, under its type" do
      id = Entity.generate_id()

      envelope = encode_deltas_envelope(42, @cursor, [keep_hashed(Module2, "q3Vx", [id])], nil)

      assert decoded_deltas(envelope) == %{
               "keep_hashed" => %{
                 "Hologram.Test.Fixtures.Entity.Module2" => [
                   %{"hashes" => [drop_hash("q3Vx", id)], "salt" => "q3Vx"}
                 ]
               }
             }
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

      assert encode_deltas_envelope(42, @cursor, [put_entity(row, %{})], nil) ==
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
      envelope = encode_deltas_envelope(42, @cursor, deltas(news, nil), nil)

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
                     "server_created_at" => nil,
                     "server_updated_at" => nil,
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
                     "server_created_at" => nil,
                     "server_updated_at" => nil,
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
        news(%{
          edges: [edge],
          patched: [{row, %{c: "after"}, nil}],
          unsynced: [{gone_id, Module2}]
        })

      envelope = encode_deltas_envelope(42, @cursor, deltas(news, nil), nil)

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

      envelope = encode_deltas_envelope(42, @cursor, [put_entity(row, %{})], nil)

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

  describe "encode_rules_envelope/3" do
    # The rules arrive rendered, so they are carried as JSON rather than as a string holding it.
    test "wraps the rules and their hash in a sync_rules SSE event envelope" do
      rules = ~s({"derived":{},"inverses":{},"policies":{}})

      assert "event: sync_rules\nid: 42\ndata: " <> data =
               encode_rules_envelope(42, "0123456789abcdef", rules)

      assert String.ends_with?(data, "\n\n")

      assert Jason.decode!(data) == %{
               "policy_hash" => "0123456789abcdef",
               "protocol_version" => 1,
               "rules" => %{"derived" => %{}, "inverses" => %{}, "policies" => %{}}
             }
    end
  end

  describe "encode_synced_envelope/3" do
    test "wraps the completeness marker in a synced SSE event envelope" do
      payload = %{
        cursor: nil,
        protocol_version: 1,
        scope: :types,
        types: ["Hologram.Test.Fixtures.Entity.Module2"]
      }

      encoded = Jason.encode!(payload)

      assert encode_synced_envelope(42, {:types, [Module2]}, nil) ==
               "event: synced\nid: 42\ndata: #{encoded}\n\n"
    end

    test "names every entity type it says is complete, the way a frame names a row's type" do
      payload = %{
        cursor: nil,
        protocol_version: 1,
        scope: :types,
        types: ["Hologram.Test.Fixtures.Entity.Module2", "Hologram.Test.Fixtures.Entity.Module3"]
      }

      encoded = Jason.encode!(payload)

      assert encode_synced_envelope(42, {:types, [Module2, Module3]}, nil) ==
               "event: synced\nid: 42\ndata: #{encoded}\n\n"
    end

    test "says which queries the client may now answer itself" do
      payload = %{cursor: nil, protocol_version: 1, scope: :all}
      encoded = Jason.encode!(payload)

      assert encode_synced_envelope(42, :all, nil) ==
               "event: synced\nid: 42\ndata: #{encoded}\n\n"
    end

    # The marker is the moment a place becomes a claim the client can honour, and for a client that
    # is filled and then left alone it is the only frame that will ever carry one.
    test "hands over the place the client may come back from" do
      payload = %{cursor: "Nzc4LjA", protocol_version: 1, scope: :all}
      encoded = Jason.encode!(payload)

      assert encode_synced_envelope(42, :all, "Nzc4LjA") ==
               "event: synced\nid: 42\ndata: #{encoded}\n\n"
    end
  end

  describe "protocol_version/0" do
    test "returns the version this build speaks" do
      assert protocol_version() == 1
    end
  end

  describe "put_entity/2" do
    test "hands over the whole row, under the type the row itself names" do
      row = Module2.new(a: true, c: "first")

      assert put_entity(row, %{}) == %{
               data: WireData.row(row),
               id: row.id,
               op: :put_entity,
               type: "Hologram.Test.Fixtures.Entity.Module2"
             }
    end

    test "carries the verdicts beside the row's data" do
      row = VerdictTask.new()

      assert put_entity(row, %{"delete:abc" => true}).data ==
               row
               |> WireData.row()
               |> Map.put(:"$verdicts", %{"delete:abc" => true})
    end

    test "carries no verdicts key when there are none" do
      row = Module2.new(a: true)

      assert put_entity(row, %{}).data == WireData.row(row)
    end
  end

  describe "row_verdicts/2" do
    test "answers the row's deciding quantifiers for the user when a client checks permissions" do
      check_permissions()

      assert row_verdicts(Entity.generate_id(), VerdictTask.new()) == %{delete_key() => true}
      assert row_verdicts(nil, VerdictTask.new()) == %{delete_key() => false}
    end

    test "answers nothing when no client checks permissions" do
      stub_with(QueryCacheMock, QueryCacheStub)
      :persistent_term.put(QueryCacheStub.persistent_term_key(), %{permission_checking?: false})

      on_exit(fn -> :persistent_term.erase(QueryCacheStub.persistent_term_key()) end)

      assert row_verdicts(Entity.generate_id(), VerdictTask.new()) == %{}
    end

    # Nothing to answer, so whether a client checks permissions is never asked - the query cache is
    # not stubbed here.
    test "answers nothing for a type with no deciding quantifier" do
      assert row_verdicts(nil, Module2.new(a: true)) == %{}
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

  describe "keep_hashed/3" do
    test "names the given rows of the given type to keep by their hashes under the given salt" do
      id = Entity.generate_id()

      assert keep_hashed(Module2, "q3Vx", [id]) == %{
               data: %{hashes: [drop_hash("q3Vx", id)], salt: "q3Vx"},
               op: :keep_hashed,
               type: "Hologram.Test.Fixtures.Entity.Module2"
             }
    end
  end

  describe "unsync_hashed/3" do
    test "names the given rows of the given type by their hashes under the given salt" do
      [first, second] = [Entity.generate_id(), Entity.generate_id()]

      assert unsync_hashed(Module2, "q3Vx", [first, second]) == %{
               data: %{
                 hashes: [drop_hash("q3Vx", first), drop_hash("q3Vx", second)],
                 salt: "q3Vx"
               },
               op: :unsync_hashed,
               type: "Hologram.Test.Fixtures.Entity.Module2"
             }
    end
  end
end
