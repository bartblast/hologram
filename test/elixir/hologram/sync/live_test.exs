defmodule Hologram.Sync.LiveTest do
  # async: false - the tests of route/4 write the query cache's persistent term, shared by the whole
  # node, and start the session registry under its registered name.
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.Sync.Live
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Auth
  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.EntityOperations
  alias Hologram.DB.Oplog
  alias Hologram.Policy.Edges
  alias Hologram.Sync.Frame
  alias Hologram.Sync.PackedIds
  alias Hologram.Sync.Sessions
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module30
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyModule1
  alias Hologram.Test.Fixtures.Policy.Module17, as: PolicyModule17
  alias Hologram.Test.Fixtures.Policy.Module18, as: PolicyModule18
  alias Hologram.Test.Fixtures.Policy.Module19, as: PolicyModule19
  alias Hologram.Test.Fixtures.Policy.Module20, as: PolicyModule20
  alias Hologram.Test.Fixtures.Policy.Module21, as: PolicyModule21
  alias Hologram.Test.Fixtures.Policy.Readers.Module15, as: ReadersModule15
  alias Hologram.Test.Fixtures.Policy.Readers.Module16, as: ReadersModule16

  use_module_stub :query_cache

  setup :set_mox_global

  @place {100, 1_000, 1_700_000_000_000_000}

  # Module17 is readable when public, or by the users holding a membership of it (Module18). A
  # membership is readable when its seat is full. Module19 is a label, which no rule admits.
  @synced [PolicyModule17, PolicyModule18, PolicyModule19]

  # The recheck asks whether the build has a client checking permissions before it works verdicts
  # out (see `Hologram.Sync.Recheck.run/2`).
  setup do
    stub_with(QueryCacheMock, QueryCacheStub)
    :persistent_term.put(QueryCacheStub.persistent_term_key(), %{permission_checking?: true})

    on_exit(fn -> :persistent_term.erase(QueryCacheStub.persistent_term_key()) end)

    :ok
  end

  setup do
    alice = create!(Module14, email: "alice@example.com")
    bob = create!(Module14, email: "bob@example.com")

    sessions = [{self(), alice.id}, {self(), bob.id}, {self(), nil}]

    %{alice: alice.id, bob: bob.id, edges: Edges.derive(@synced), sessions: sessions}
  end

  defp create!(entity_type, values \\ []) do
    values
    |> entity_type.new()
    |> DB.create!()
  end

  # An effect as the log reads it back: data and old references keyed by strings.
  defp effect(op, entity_type, entity_id, data, opts \\ []) do
    %{
      data: data,
      entity_id: entity_id,
      mutation_ref: Keyword.get(opts, :mutation_ref),
      inserted_at: ~U[2026-11-24 00:00:00Z],
      old: nil,
      op: op,
      seq: Keyword.get(opts, :seq, 100),
      tx: Keyword.get(opts, :tx, 1_000),
      type: entity_type
    }
  end

  defp log_batch(row, tx, replica_id, seq) do
    statement = """
    INSERT INTO "hologram_system"."oplog" ("op", "type", "entity_id", "tx", "model_hash", "mutation_ref")
    VALUES ('patch_entity', $1, $2, $3::text::xid8, 'h', $4)
    RETURNING "seq"
    """

    params = [
      Codec.encode_enum_value(row.__struct__),
      Codec.encode(row.id, :uuid),
      Integer.to_string(tx),
      %{"replica_id" => replica_id, "seq" => seq}
    ]

    {:ok, %Postgrex.Result{rows: [[logged_seq]]}} = Connection.query(statement, params)

    logged_seq
  end

  # What a part's packed ids hold, per entity type.
  defp unpacked(packed_by_type) do
    Map.new(packed_by_type, fn {entity_type, packed} ->
      {entity_type, MapSet.new(PackedIds.unpack(packed))}
    end)
  end

  defp unpacked_pairs(packed_by_key) do
    Map.new(packed_by_key, fn {key, packed} -> {key, PackedIds.unpack_pairs(packed)} end)
  end

  # What a session would work out for the given user on the row as it stands now.
  defp worked_out_verdicts(user_id, row) do
    Frame.row_verdicts(user_id, DB.read(row.__struct__, row.id))
  end

  defp ids(rows) do
    rows
    |> Enum.map(& &1.id)
    |> MapSet.new()
  end

  defp pair_effect(op, source, relationship_name, target) do
    data = %{"relationship" => Atom.to_string(relationship_name), "target_id" => target.id}

    effect(op, source.__struct__, source.id, data)
  end

  # A session of the given user in a process of its own, passing on what it is sent.
  defp start_forwarding_session(user_id) do
    test_pid = self()

    spawn_link(fn ->
      Sessions.register(user_id)
      send(test_pid, :registered)
      forward(test_pid)
    end)

    assert_receive :registered
  end

  defp forward(test_pid) do
    receive do
      message ->
        send(test_pid, {:forwarded, message})
        forward(test_pid)
    end
  end

  defp link!(source, relationship_name, target) do
    :ok =
      EntityOperations.add_relationship(
        source.__struct__,
        source.id,
        relationship_name,
        target.id
      )
  end

  # The query cache route/4 reads: whether a client checks permissions, and the synced types.
  defp route_query_cache(permission_checking?) do
    %{derived: %{}, permission_checking?: permission_checking?, synced_types: @synced}
  end

  defp readable_ids(part, entity_type) do
    part.readable
    |> Map.get(entity_type, %{})
    |> Map.keys()
    |> MapSet.new()
  end

  describe "parts/7" do
    test "checks the row a patch wrote, and gives it to whoever may read it", context do
      project = create!(PolicyModule17, public: true)
      effects = [effect(:patch_entity, PolicyModule17, project.id, %{"name" => "renamed"})]

      parts = parts(effects, context.sessions, context.edges, @synced, @place)

      for user_id <- [context.alice, context.bob, nil] do
        part = Map.fetch!(parts, user_id)

        assert unpacked(part.checked) == %{PolicyModule17 => ids([project])}
        assert %{PolicyModule17 => %{} = rows} = part.readable
        assert %PolicyModule17{name: nil, public: true} = Map.fetch!(rows, project.id)
      end
    end

    test "moves a row a patch wrote an attribute of that its read rule reads", context do
      project = create!(PolicyModule17)
      effects = [effect(:patch_entity, PolicyModule17, project.id, %{"public" => false})]

      parts = parts(effects, context.sessions, context.edges, @synced, @place)

      assert unpacked(parts[nil].moved) == %{PolicyModule17 => ids([project])}
    end

    test "moves nothing of a row a patch wrote no attribute of that its read rule reads",
         context do
      project = create!(PolicyModule17)
      effects = [effect(:patch_entity, PolicyModule17, project.id, %{"name" => "renamed"})]

      parts = parts(effects, context.sessions, context.edges, @synced, @place)

      assert parts[nil].moved == %{}
    end

    test "moves a row created or deleted", context do
      created = create!(PolicyModule17)
      deleted_id = Ecto.UUID.generate()

      effects = [
        effect(:put_entity, PolicyModule17, created.id, %{"name" => nil, "public" => false}),
        effect(:del_entity, PolicyModule17, deleted_id, %{"name" => nil, "public" => false})
      ]

      parts = parts(effects, context.sessions, context.edges, @synced, @place)

      assert unpacked(parts[nil].moved) == %{
               PolicyModule17 => MapSet.new([created.id, deleted_id])
             }
    end

    test "moves the rows the search reaches", context do
      project = create!(PolicyModule17)
      membership = create!(PolicyModule18, project_id: project.id, user_id: context.alice)

      effects = [
        effect(:patch_entity, PolicyModule18, membership.id, %{"user_id" => context.bob})
      ]

      parts = parts(effects, context.sessions, context.edges, @synced, @place)

      assert MapSet.member?(unpacked(parts[nil].moved)[PolicyModule17], project.id)
    end

    test "gives a row only to the users who may read it", context do
      project = create!(PolicyModule17)
      create!(PolicyModule18, project_id: project.id, user_id: context.alice)

      effects = [effect(:patch_entity, PolicyModule17, project.id, %{"name" => "renamed"})]

      parts = parts(effects, context.sessions, context.edges, @synced, @place)

      assert readable_ids(parts[context.alice], PolicyModule17) == ids([project])
      assert readable_ids(parts[context.bob], PolicyModule17) == MapSet.new()
      assert readable_ids(parts[nil], PolicyModule17) == MapSet.new()
      assert unpacked(parts[context.bob].checked) == %{PolicyModule17 => ids([project])}
    end

    # The membership names its project, whose read rule reads the set the membership joins.
    test "checks the rows a write moves the read access of", context do
      project = create!(PolicyModule17)

      membership =
        create!(PolicyModule18, project_id: project.id, seat: "full", user_id: context.bob)

      data = %{"project_id" => project.id, "seat" => "full", "user_id" => context.bob}
      effects = [effect(:put_entity, PolicyModule18, membership.id, data)]

      parts = parts(effects, context.sessions, context.edges, @synced, @place)

      assert unpacked(parts[context.bob].checked) == %{
               PolicyModule17 => ids([project]),
               PolicyModule18 => ids([membership])
             }

      assert readable_ids(parts[context.bob], PolicyModule17) == ids([project])
      assert readable_ids(parts[context.alice], PolicyModule17) == MapSet.new()
    end

    test "checks a deleted row, which nobody may read any more", context do
      project = create!(PolicyModule17, public: true)
      deleted_id = Ecto.UUID.generate()

      effects = [
        effect(:del_entity, PolicyModule17, deleted_id, %{"name" => nil, "public" => true}),
        effect(:patch_entity, PolicyModule17, project.id, %{"name" => "kept"})
      ]

      parts = parts(effects, context.sessions, context.edges, @synced, @place)
      part = Map.fetch!(parts, nil)

      assert unpacked(part.checked) == %{PolicyModule17 => MapSet.new([deleted_id, project.id])}
      assert readable_ids(part, PolicyModule17) == ids([project])
    end

    test "checks both ends of a pair and lists the pair once", context do
      project = create!(PolicyModule17, public: true)
      label = create!(PolicyModule19)

      effects = [
        pair_effect(:add_relationship, project, :labels, label),
        pair_effect(:del_relationship, project, :labels, label),
        pair_effect(:add_relationship, project, :labels, label)
      ]

      parts = parts(effects, context.sessions, context.edges, @synced, @place)
      part = Map.fetch!(parts, nil)

      assert unpacked(part.checked) == %{
               PolicyModule17 => ids([project]),
               PolicyModule19 => ids([label])
             }

      assert unpacked_pairs(part.pair_effects) == %{
               {PolicyModule17, :labels, PolicyModule19} => [{project.id, label.id}]
             }
    end

    test "gives every part the pairs touching the checked rows as they stand now", context do
      project = create!(PolicyModule17, public: true)
      kept_label = create!(PolicyModule19)
      removed_label = create!(PolicyModule19)

      link!(project, :labels, kept_label)

      effects = [
        effect(:patch_entity, PolicyModule17, project.id, %{"name" => "renamed"}),
        pair_effect(:del_relationship, project, :labels, removed_label)
      ]

      parts = parts(effects, context.sessions, context.edges, @synced, @place)

      for part <- Map.values(parts) do
        assert unpacked_pairs(part.pairs) == %{
                 {PolicyModule17, :labels, PolicyModule19} => [{project.id, kept_label.id}]
               }
      end
    end

    test "names a pair's target in the form every listed id takes", context do
      project = create!(PolicyModule17, public: true)
      label = create!(PolicyModule19)

      data = %{"relationship" => "labels", "target_id" => String.replace(label.id, "-", "")}
      effects = [effect(:add_relationship, PolicyModule17, project.id, data)]

      parts = parts(effects, context.sessions, context.edges, @synced, @place)
      part = Map.fetch!(parts, nil)

      assert unpacked_pairs(part.pair_effects) == %{
               {PolicyModule17, :labels, PolicyModule19} => [{project.id, label.id}]
             }
    end

    test "dates every part's numbers as final up to the given seq", context do
      project = create!(PolicyModule17, public: true)
      effects = [effect(:patch_entity, PolicyModule17, project.id, %{"name" => "renamed"})]

      parts = parts(effects, context.sessions, context.edges, @synced, @place, nil, 250)

      for user_id <- [context.alice, context.bob, nil] do
        assert Map.fetch!(parts, user_id).final_seq == 250
      end
    end

    test "dates every part's numbers as final up to its place given no seq", context do
      project = create!(PolicyModule17, public: true)
      effects = [effect(:patch_entity, PolicyModule17, project.id, %{"name" => "renamed"})]

      parts = parts(effects, context.sessions, context.edges, @synced, @place)

      assert Map.fetch!(parts, nil).final_seq == 100
    end

    test "leaves out the rows and pairs of a type sync doesn't send", context do
      project = create!(PolicyModule17, public: true)
      label = create!(PolicyModule19)

      effects = [
        pair_effect(:add_relationship, project, :labels, label),
        effect(:patch_entity, PolicyModule19, label.id, %{"name" => "renamed"})
      ]

      synced = [PolicyModule17, PolicyModule18]
      parts = parts(effects, context.sessions, context.edges, synced, @place)
      part = Map.fetch!(parts, nil)

      assert unpacked(part.checked) == %{PolicyModule17 => ids([project])}
      assert part.pair_effects == %{}
    end

    test "passes over an effect of an entity type this node doesn't know", context do
      effects = [effect(:patch_entity, "MyApp.Unknown", Ecto.UUID.generate(), %{"a" => 1})]

      parts = parts(effects, context.sessions, context.edges, @synced, @place)
      part = Map.fetch!(parts, nil)

      assert unpacked(part.checked) == %{}
      assert part.written == %{}
    end

    test "passes over a pair of a to-many this build doesn't declare", context do
      project = create!(PolicyModule17, public: true)

      data = %{"relationship" => "watchers", "target_id" => Ecto.UUID.generate()}
      effects = [effect(:add_relationship, PolicyModule17, project.id, data)]

      parts = parts(effects, context.sessions, context.edges, @synced, @place)
      part = Map.fetch!(parts, nil)

      assert part.pair_effects == %{}
    end

    test "gives the users of several sessions one part each", context do
      project = create!(PolicyModule17, public: true)
      effects = [effect(:patch_entity, PolicyModule17, project.id, %{"name" => "renamed"})]

      sessions = [{self(), context.alice}, {self(), context.alice}, {self(), nil}]

      parts = parts(effects, sessions, context.edges, @synced, @place)

      user_ids =
        parts
        |> Map.keys()
        |> Enum.sort()

      assert user_ids == Enum.sort([context.alice, nil])
    end

    test "names what the batch is about the same way in every part", context do
      project = create!(PolicyModule17, public: true)

      effects = [
        effect(:patch_entity, PolicyModule17, project.id, %{"public" => true}, seq: 101),
        effect(:patch_entity, PolicyModule17, project.id, %{"name" => "renamed"}, seq: 100)
      ]

      parts = parts(effects, context.sessions, context.edges, @synced, @place)

      for part <- Map.values(parts) do
        assert part.place == @place
        assert part.synced_types == @synced
        assert part.seq_range == {100, 101}

        assert part.written == %{
                 project.id => MapSet.new(["name", "public", "server_updated_seq"])
               }
      end
    end

    test "names the highest batch of each replica the effects came from", context do
      project = create!(PolicyModule17, public: true)

      effects = [
        effect(:patch_entity, PolicyModule17, project.id, %{"name" => "a"},
          mutation_ref: %{"replica_id" => "replica_a", "seq" => 3}
        ),
        effect(:patch_entity, PolicyModule17, project.id, %{"name" => "b"},
          mutation_ref: %{"replica_id" => "replica_a", "seq" => 7}
        ),
        effect(:patch_entity, PolicyModule17, project.id, %{"name" => "c"},
          mutation_ref: %{"replica_id" => "replica_b", "seq" => 2}
        ),
        effect(:patch_entity, PolicyModule17, project.id, %{"name" => "d"})
      ]

      parts = parts(effects, context.sessions, context.edges, @synced, @place)
      part = Map.fetch!(parts, nil)

      assert part.own_seqs == %{"replica_a" => 7, "replica_b" => 2}
    end

    test "names the rows each replica's batches put, per entity type", context do
      project_1 = create!(PolicyModule17)
      project_2 = create!(PolicyModule17)
      label = create!(PolicyModule19)

      effects = [
        effect(:put_entity, PolicyModule17, project_1.id, %{"name" => nil, "public" => false},
          mutation_ref: %{"replica_id" => "replica_a", "seq" => 1}
        ),
        effect(:put_entity, PolicyModule19, label.id, %{"name" => nil},
          mutation_ref: %{"replica_id" => "replica_a", "seq" => 2}
        ),
        effect(:put_entity, PolicyModule17, project_2.id, %{"name" => nil, "public" => false},
          mutation_ref: %{"replica_id" => "replica_b", "seq" => 1}
        )
      ]

      parts = parts(effects, context.sessions, context.edges, @synced, @place)
      part = Map.fetch!(parts, nil)

      assert Map.new(part.own_puts, fn {replica_id, puts} -> {replica_id, unpacked(puts)} end) ==
               %{
                 "replica_a" => %{
                   PolicyModule17 => ids([project_1]),
                   PolicyModule19 => ids([label])
                 },
                 "replica_b" => %{PolicyModule17 => ids([project_2])}
               }
    end

    test "names no row a replica's batches patched, deleted or put of a type sync doesn't send",
         context do
      project = create!(PolicyModule17)
      label = create!(PolicyModule19)
      ref = %{"replica_id" => "replica_a", "seq" => 1}

      effects = [
        effect(:patch_entity, PolicyModule17, project.id, %{"name" => "a"}, mutation_ref: ref),
        effect(:del_entity, PolicyModule17, Ecto.UUID.generate(), %{}, mutation_ref: ref),
        effect(:put_entity, PolicyModule19, label.id, %{"name" => nil}, mutation_ref: ref)
      ]

      synced = [PolicyModule17, PolicyModule18]
      parts = parts(effects, context.sessions, context.edges, synced, @place)

      assert Map.fetch!(parts, nil).own_puts == %{}
    end

    test "names no row a put with no batch made", context do
      project = create!(PolicyModule17)

      effects = [
        effect(:put_entity, PolicyModule17, project.id, %{"name" => nil, "public" => false})
      ]

      parts = parts(effects, context.sessions, context.edges, @synced, @place)

      assert Map.fetch!(parts, nil).own_puts == %{}
    end

    # Module17's archive rule reads none(label <- labels, label.name == "locked"), which a browser
    # can't decide, so a renamed label moves the verdicts of the projects holding it.
    test "gives the verdicts of the rows the batch may have moved them of, as they stand now",
         context do
      project = create!(PolicyModule17, public: true)
      other_project = create!(PolicyModule17, public: true)
      label = create!(PolicyModule19)

      link!(project, :labels, label)
      DB.update!(PolicyModule19, label.id, name: "locked")

      effects = [
        effect(:patch_entity, PolicyModule19, label.id, %{"name" => "locked"}),
        effect(:patch_entity, PolicyModule17, other_project.id, %{"name" => "renamed"})
      ]

      parts = parts(effects, context.sessions, context.edges, @synced, @place)
      part = Map.fetch!(parts, nil)

      assert part.verdicts == %{
               PolicyModule17 => %{
                 project.id => worked_out_verdicts(nil, project),
                 other_project.id => worked_out_verdicts(nil, other_project)
               }
             }

      refute part.verdicts[PolicyModule17][project.id] ==
               part.verdicts[PolicyModule17][other_project.id]
    end

    # The board's verdicts depend on who asks: Alice wrote a card on it, so she can't archive it,
    # while Bob, whom no card names, answers what a reader no clause anchors on does.
    test "gives each reader the verdicts that reader has", context do
      synced = [ReadersModule15, ReadersModule16]
      board = create!(ReadersModule15)
      create!(ReadersModule16, author_id: context.alice, board_id: board.id)

      effects = [effect(:patch_entity, ReadersModule15, board.id, %{"name" => "renamed"})]
      parts = parts(effects, context.sessions, Edges.derive(synced), synced, @place)

      for user_id <- [context.alice, context.bob, nil] do
        assert parts[user_id].verdicts[ReadersModule15][board.id] ==
                 worked_out_verdicts(user_id, board)
      end

      refute parts[context.alice].verdicts[ReadersModule15][board.id] ==
               parts[context.bob].verdicts[ReadersModule15][board.id]
    end

    # A user id in any spelling but the one Hologram generates names no user entity, so it reads -
    # and gets the verdicts of - an anonymous user, not those of a reader no card names.
    test "gives a user id in another spelling the verdicts of an anonymous user", context do
      synced = [ReadersModule15, ReadersModule16]
      board = create!(ReadersModule15)
      create!(ReadersModule16, author_id: context.alice, board_id: board.id)

      shouted = String.upcase(context.alice)
      effects = [effect(:patch_entity, ReadersModule15, board.id, %{"name" => "renamed"})]

      parts =
        parts(effects, [{self(), shouted}, {self(), 42}], Edges.derive(synced), synced, @place)

      anonymous = worked_out_verdicts(nil, board)

      assert parts[shouted].verdicts[ReadersModule15][board.id] == anonymous
      assert parts[42].verdicts[ReadersModule15][board.id] == anonymous
      refute worked_out_verdicts(context.bob, board) == anonymous
    end

    test "gives verdicts of the rows its user may read alone", context do
      project = create!(PolicyModule17, public: false)
      effects = [effect(:patch_entity, PolicyModule17, project.id, %{"name" => "renamed"})]

      create!(PolicyModule18, project_id: project.id, seat: "full", user_id: context.alice)

      parts = parts(effects, context.sessions, context.edges, @synced, @place)

      assert Map.keys(parts[context.alice].verdicts[PolicyModule17]) == [project.id]
      assert parts[context.bob].verdicts[PolicyModule17] == %{}
      assert parts[nil].verdicts[PolicyModule17] == %{}
    end

    # Read with the rows, so a replica's batch with an entry above the place counts, also one
    # committed into the seqs below the effects' highest, which a save running when the effects were
    # read held, while one with entries only at or below the place doesn't.
    test "gives each replica's highest batch with an entry above the place", context do
      project = create!(PolicyModule17, public: true)

      place_seq = log_batch(project, 2_000, "replica_c", 5)
      log_batch(project, 2_001, "replica_b", 3)
      batch_seq = log_batch(project, 2_002, "replica_a", 8)

      effects = [
        effect(:patch_entity, PolicyModule17, project.id, %{"name" => "renamed"}, seq: batch_seq)
      ]

      place = {place_seq, 2_000, 1_700_000_000_000_000}
      parts = parts(effects, context.sessions, context.edges, @synced, place)

      assert parts[nil].overtaking_seqs == %{"replica_a" => 8, "replica_b" => 3}
      assert parts[context.alice].overtaking_seqs == %{"replica_a" => 8, "replica_b" => 3}
    end

    test "names the types a grant moved every row of, for its holder alone", context do
      edges = %{{PolicyModule1, :read} => [{:own_grants, [:viewer]}]}
      user = DB.read(Module14, context.alice)

      before = Oplog.read_type_after(RoleGrant, 0, %{})
      Auth.grant_role(user, :viewer, PolicyModule1)

      effects =
        RoleGrant
        |> Oplog.read_type_after(0, %{})
        |> Enum.drop(length(before))
        |> Enum.map(&Map.put(&1, :mutation_ref, nil))

      parts = parts(effects, context.sessions, edges, [PolicyModule1], @place)

      assert parts[context.alice].whole_types == [PolicyModule1]
      assert parts[context.bob].whole_types == []
      assert parts[nil].whole_types == []
    end

    test "leaves out the types sync doesn't send from what a grant moved", context do
      edges = %{{PolicyModule1, :read} => [{:own_grants, [:viewer]}]}

      data = %{
        "entity_id" => nil,
        "entity_type" => "Hologram.Test.Fixtures.Policy.Module1",
        "role" => "viewer",
        "user_id" => context.alice
      }

      effects = [effect(:put_entity, RoleGrant, Ecto.UUID.generate(), data)]

      parts = parts(effects, context.sessions, edges, @synced, @place)

      assert parts[context.alice].whole_types == []
    end

    test "gives the verdicts of a pair's ends", context do
      project = create!(PolicyModule17, public: true)
      label = create!(PolicyModule19)

      effects = [pair_effect(:add_relationship, project, :labels, label)]

      parts = parts(effects, context.sessions, context.edges, @synced, @place)
      part = Map.fetch!(parts, nil)

      assert part.verdicts == %{
               PolicyModule17 => %{project.id => worked_out_verdicts(nil, project)}
             }
    end

    test "leaves out of the verdicts a type sync doesn't send", context do
      project = create!(PolicyModule17, public: true)
      effects = [effect(:patch_entity, PolicyModule17, project.id, %{"name" => "renamed"})]

      parts = parts(effects, context.sessions, context.edges, [PolicyModule18], @place)
      part = Map.fetch!(parts, nil)

      assert part.verdicts == %{}
    end

    test "passes over an effect whose type names a module that is no entity", context do
      effects = [effect(:patch_entity, String, Ecto.UUID.generate(), %{"a" => 1})]

      parts = parts(effects, context.sessions, context.edges, @synced, @place)
      part = Map.fetch!(parts, nil)

      assert part.checked == %{}
      assert part.pair_effects == %{}
      assert part.verdicts == %{}
    end

    test "names what a patch or a put wrote, and nothing for a delete", context do
      project = create!(PolicyModule17, public: true)
      other_project = create!(PolicyModule17, public: true)

      effects = [
        effect(:put_entity, PolicyModule17, project.id, %{"name" => nil, "public" => true}),
        effect(:del_entity, PolicyModule17, other_project.id, %{"name" => nil, "public" => true})
      ]

      parts = parts(effects, context.sessions, context.edges, @synced, @place)
      part = Map.fetch!(parts, nil)

      assert part.written == %{
               project.id =>
                 MapSet.new(["name", "public", "server_created_seq", "server_updated_seq"])
             }
    end

    test "names what was written of the rows the user may read alone", context do
      project = create!(PolicyModule17)
      create!(PolicyModule18, project_id: project.id, user_id: context.alice)

      effects = [effect(:patch_entity, PolicyModule17, project.id, %{"name" => "renamed"})]

      parts = parts(effects, context.sessions, context.edges, @synced, @place)

      assert parts[context.alice].written == %{
               project.id => MapSet.new(["name", "server_updated_seq"])
             }

      assert parts[context.bob].written == %{}
    end

    test "counts a batch towards its replica's number whatever type its effect is of", context do
      ref = %{"replica_id" => "replica_a", "seq" => 4}

      effects = [
        effect(:patch_entity, "MyApp.Unknown", Ecto.UUID.generate(), %{}, mutation_ref: ref)
      ]

      parts = parts(effects, context.sessions, context.edges, @synced, @place)
      part = Map.fetch!(parts, nil)

      assert part.own_seqs == %{"replica_a" => 4}
    end

    # Past 5,000 ids of one type (the recheck's chunk size in Hologram.Sync.Live) the recheck asks in
    # several statements, so 5,203 take two.
    test "asks about many rows of one type in several statements, as if in one", context do
      projects = for _index <- 1..3, do: create!(PolicyModule17, public: true)
      missing_ids = for _index <- 1..5_200, do: Ecto.UUID.generate()

      effects =
        projects
        |> Enum.map(& &1.id)
        |> Enum.concat(missing_ids)
        |> Enum.map(&effect(:patch_entity, PolicyModule17, &1, %{"name" => "renamed"}))

      parts = parts(effects, context.sessions, context.edges, @synced, @place)
      part = Map.fetch!(parts, nil)

      assert readable_ids(part, PolicyModule17) == ids(projects)

      verdict_ids =
        part.verdicts[PolicyModule17]
        |> Map.keys()
        |> MapSet.new()

      assert verdict_ids == ids(projects)
      assert MapSet.size(unpacked(part.checked)[PolicyModule17]) == 5_203
    end

    test "gives the sessions of one user the same part", context do
      project = create!(PolicyModule17)
      create!(PolicyModule18, project_id: project.id, user_id: context.alice)

      effects = [effect(:patch_entity, PolicyModule17, project.id, %{"name" => "renamed"})]

      alone = parts(effects, [{self(), context.alice}], context.edges, @synced, @place)

      together =
        parts(
          effects,
          [{self(), context.alice}, {self(), context.alice}, {self(), context.bob}],
          context.edges,
          @synced,
          @place
        )

      assert together[context.alice] == alone[context.alice]
    end
  end

  describe "part/6" do
    test "answers the part of the given user, as parts/7 answers it for a session of theirs",
         context do
      project = create!(PolicyModule17)
      create!(PolicyModule18, project_id: project.id, user_id: context.alice)

      effects = [effect(:patch_entity, PolicyModule17, project.id, %{"name" => "renamed"})]

      part = part(effects, context.alice, context.edges, @synced, @place, 0)

      assert readable_ids(part, PolicyModule17) == ids([project])
      assert part.place == @place
    end

    test "gives each replica's highest batch with an entry above the given seq", context do
      project = create!(PolicyModule17, public: true)

      first_seq = log_batch(project, 2_000, "replica_b", 3)
      last_seq = log_batch(project, 2_001, "replica_a", 8)

      effects = [
        effect(:patch_entity, PolicyModule17, project.id, %{"name" => "renamed"}, seq: last_seq)
      ]

      part = part(effects, context.alice, context.edges, @synced, @place, first_seq - 1)

      assert part.overtaking_seqs == %{"replica_a" => 8, "replica_b" => 3}
    end
  end

  describe "pairs_touching/2" do
    test "returns the pairs a given row is the source of" do
      project = create!(PolicyModule17)
      other_project = create!(PolicyModule17)
      labels = [create!(PolicyModule19), create!(PolicyModule19)]

      Enum.each(labels, &link!(project, :labels, &1))
      link!(other_project, :labels, create!(PolicyModule19))

      pairs = pairs_touching(%{PolicyModule17 => [project.id]}, @synced)

      expected =
        labels
        |> Enum.map(&{project.id, &1.id})
        |> Enum.sort()

      assert unpacked_pairs(pairs) == %{{PolicyModule17, :labels, PolicyModule19} => expected}
    end

    test "returns the pairs a given row is the target of" do
      label = create!(PolicyModule19)
      projects = [create!(PolicyModule17), create!(PolicyModule17)]

      Enum.each(projects, &link!(&1, :labels, label))
      link!(create!(PolicyModule17), :labels, create!(PolicyModule19))

      pairs = pairs_touching(%{PolicyModule19 => MapSet.new([label.id])}, @synced)

      expected =
        projects
        |> Enum.map(&{&1.id, label.id})
        |> Enum.sort()

      assert unpacked_pairs(pairs) == %{{PolicyModule17, :labels, PolicyModule19} => expected}
    end

    test "returns the pairs of a to-many whose target files an inverse of it" do
      task = create!(PolicyModule20)
      tag = create!(PolicyModule21)

      link!(task, :tags, tag)

      pairs = pairs_touching(%{PolicyModule21 => [tag.id]}, [PolicyModule20, PolicyModule21])

      assert unpacked_pairs(pairs) == %{
               {PolicyModule20, :tags, PolicyModule21} => [{task.id, tag.id}]
             }
    end

    test "leaves out the pairs of a to-many whose target type sync doesn't send" do
      project = create!(PolicyModule17)
      link!(project, :labels, create!(PolicyModule19))

      assert pairs_touching(%{PolicyModule17 => [project.id]}, [PolicyModule17]) == %{}
    end

    test "leaves out the pairs of a to-many whose source type sync doesn't send" do
      label = create!(PolicyModule19)
      link!(create!(PolicyModule17), :labels, label)

      assert pairs_touching(%{PolicyModule19 => [label.id]}, [PolicyModule19]) == %{}
    end

    test "leaves out a relationship no given row has a pair of" do
      project = create!(PolicyModule17)

      assert pairs_touching(%{PolicyModule17 => [project.id]}, @synced) == %{}
    end

    # The rows are linked out of their id order, so a pair read in any order but by source and then
    # target packs to other bytes. Two ids made in one millisecond can come out either way round,
    # hence the sort.
    test "returns the pairs in the order pack_pairs/1 packs them" do
      [first_project, second_project] =
        Enum.sort_by([create!(PolicyModule17), create!(PolicyModule17)], & &1.id)

      [first_label, second_label] =
        Enum.sort_by([create!(PolicyModule19), create!(PolicyModule19)], & &1.id)

      link!(second_project, :labels, first_label)
      link!(first_project, :labels, second_label)
      link!(first_project, :labels, first_label)

      ids_by_type = %{PolicyModule17 => [first_project.id, second_project.id]}

      expected =
        PackedIds.pack_pairs([
          {second_project.id, first_label.id},
          {first_project.id, second_label.id},
          {first_project.id, first_label.id}
        ])

      assert pairs_touching(ids_by_type, @synced) == %{
               {PolicyModule17, :labels, PolicyModule19} => expected
             }
    end

    test "returns nothing for no rows" do
      assert pairs_touching(%{}, @synced) == %{}
    end

    test "returns a pair with both ends among the given rows once" do
      project = create!(PolicyModule17)
      label = create!(PolicyModule19)

      link!(project, :labels, label)

      ids_by_type = %{PolicyModule17 => [project.id], PolicyModule19 => [label.id]}

      assert unpacked_pairs(pairs_touching(ids_by_type, @synced)) == %{
               {PolicyModule17, :labels, PolicyModule19} => [{project.id, label.id}]
             }
    end

    test "returns the pairs of every relationship a given row is at an end of, each its own" do
      project = create!(PolicyModule17)
      label = create!(PolicyModule19)
      task = create!(PolicyModule20)
      tag = create!(PolicyModule21)

      link!(project, :labels, label)
      link!(task, :tags, tag)

      ids_by_type = %{PolicyModule17 => [project.id], PolicyModule20 => [task.id]}
      synced = [PolicyModule17, PolicyModule19, PolicyModule20, PolicyModule21]

      assert unpacked_pairs(pairs_touching(ids_by_type, synced)) == %{
               {PolicyModule17, :labels, PolicyModule19} => [{project.id, label.id}],
               {PolicyModule20, :tags, PolicyModule21} => [{task.id, tag.id}]
             }
    end

    test "returns the pairs of a to-many of a type onto itself, from either end" do
      [first, second, third] = for body <- ["a", "b", "c"], do: create!(Module30, body: body)

      link!(first, :follows, second)
      link!(second, :follows, third)
      link!(third, :follows, third)

      pairs = pairs_touching(%{Module30 => [second.id, third.id]}, [Module30])

      expected = Enum.sort([{first.id, second.id}, {second.id, third.id}, {third.id, third.id}])

      assert unpacked_pairs(pairs) == %{{Module30, :follows, Module30} => expected}
    end
  end

  describe "route/4" do
    setup do
      setup_query_cache(QueryCacheStub, false)

      :persistent_term.put(QueryCacheStub.persistent_term_key(), route_query_cache(true))

      wait_for_process_cleanup(Sessions.registry())
      start_supervised!(Sessions)

      :ok
    end

    test "sends nothing on a node with no session" do
      project = create!(PolicyModule17, public: true)
      effect = effect(:patch_entity, PolicyModule17, project.id, %{"name" => "renamed"})

      assert route([effect], @place) == :ok

      refute_received {:live, _part}
    end

    test "sends each session its user's part", context do
      project = create!(PolicyModule17)
      create!(PolicyModule18, project_id: project.id, user_id: context.alice)

      effect = effect(:patch_entity, PolicyModule17, project.id, %{"name" => "renamed"})

      Sessions.register(context.alice)
      start_forwarding_session(context.bob)

      assert route([effect], @place) == :ok

      assert_received {:live, part}
      assert part.place == @place
      assert Map.keys(part.readable[PolicyModule17]) == [project.id]

      assert_receive {:forwarded, {:live, bob_part}}
      assert bob_part.readable[PolicyModule17] == %{}

      refute_received {:live, _part}
    end

    test "sends each session a part dated by the given final seq", context do
      project = create!(PolicyModule17, public: true)
      effect = effect(:patch_entity, PolicyModule17, project.id, %{"name" => "renamed"})

      Sessions.register(context.alice)

      route([effect], @place, nil, 250)

      assert_received {:live, part}
      assert part.final_seq == 250
    end

    test "tells every session how far the numbers are final when the round read nothing",
         context do
      Sessions.register(context.alice)
      start_forwarding_session(context.bob)

      assert route([], @place, nil, 250) == :ok

      assert_received {:final, 250}
      assert_receive {:forwarded, {:final, 250}}
      refute_received {:live, _part}
    end

    test "tells how far the numbers are final up to the place given no seq", context do
      Sessions.register(context.alice)

      route([], @place)

      assert_received {:final, 100}
    end

    # Module17's archive rule reads none(label <- labels, label.name == "locked"), which no read
    # rule reads - a none the server answers browsers with its verdict, which reads the labels.
    test "sends a session the rows the batch may have moved the verdicts of", context do
      project = create!(PolicyModule17, public: true)
      label = create!(PolicyModule19)
      link!(project, :labels, label)

      effect = effect(:patch_entity, PolicyModule19, label.id, %{"name" => "locked"})

      Sessions.register(context.alice)

      route([effect], @place)

      assert_received {:live, part}
      assert readable_ids(part, PolicyModule17) == MapSet.new([project.id])
    end

    test "counts the batches with an entry above the given seq sent or below it not sent as overtaking",
         context do
      project = create!(PolicyModule17, public: true)

      unsent_seq = log_batch(project, 2_000, "replica_b", 3)
      log_batch(project, 2_001, "replica_c", 5)
      batch_seq = log_batch(project, 2_002, "replica_a", 8)
      log_batch(project, 2_003, "replica_d", 9)

      effect =
        effect(:patch_entity, PolicyModule17, project.id, %{"name" => "renamed"}, seq: batch_seq)

      Sessions.register(context.alice)

      route([effect], @place, {batch_seq, [{unsent_seq, unsent_seq}]})

      assert_received {:live, part}
      assert part.overtaking_seqs == %{"replica_b" => 3, "replica_d" => 9}
    end

    # No client checks permissions, so no row carries a verdict, and a change only a verdict reads
    # moves nothing a client is sent.
    test "sends a session none of the rows only their verdicts tie to the batch when no client checks permissions",
         context do
      :persistent_term.put(QueryCacheStub.persistent_term_key(), route_query_cache(false))

      project = create!(PolicyModule17, public: true)
      label = create!(PolicyModule19)
      link!(project, :labels, label)

      effect = effect(:patch_entity, PolicyModule19, label.id, %{"name" => "locked"})

      Sessions.register(context.alice)

      route([effect], @place)

      assert_received {:live, part}
      refute Map.has_key?(part.readable, PolicyModule17)
    end
  end
end
