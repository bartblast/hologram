defmodule Hologram.Sync.LiveTest do
  # async: false - the tests of route/2 write the query cache's persistent term, shared by the whole
  # node, and start the sync result store, the evaluator registry, the evaluators supervisor and the
  # session registry under their registered names.
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.Sync.Live
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Auth
  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.EntityOperations
  alias Hologram.DB.Oplog
  alias Hologram.Policy.Edges
  alias Hologram.Query.Stage
  alias Hologram.Sync.Evaluator
  alias Hologram.Sync.Evaluators
  alias Hologram.Sync.PackedIds
  alias Hologram.Sync.ResultStore
  alias Hologram.Sync.Sessions
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyModule1
  alias Hologram.Test.Fixtures.Policy.Module17, as: PolicyModule17
  alias Hologram.Test.Fixtures.Policy.Module18, as: PolicyModule18
  alias Hologram.Test.Fixtures.Policy.Module19, as: PolicyModule19

  use_module_stub :query_cache

  setup :set_mox_global

  @place {100, 0}

  @project_window "w_project"

  # Module17 is readable when public, or by the users holding a membership of it (Module18). A
  # membership is readable when its seat is full. Module19 is a label, which no rule admits.
  @synced [PolicyModule17, PolicyModule18, PolicyModule19]

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
      old: nil,
      op: op,
      tx: Keyword.get(opts, :tx, 100),
      type: entity_type
    }
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

  defp readable_ids(part, entity_type) do
    part.readable
    |> Map.get(entity_type, %{})
    |> Map.keys()
    |> MapSet.new()
  end

  describe "parts/5" do
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
        effect(:patch_entity, PolicyModule17, project.id, %{"public" => true}, tx: 101),
        effect(:patch_entity, PolicyModule17, project.id, %{"name" => "renamed"}, tx: 100)
      ]

      parts = parts(effects, context.sessions, context.edges, @synced, @place)

      for part <- Map.values(parts) do
        assert part.place == @place
        assert part.tx_range == {100, 101}
        assert part.written == %{project.id => MapSet.new(["name", "public"])}
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

    # Module17's archive rule reads none(label <- labels, label.name == "locked"), which a browser
    # can't decide, so a renamed label moves the verdicts of the projects holding it.
    test "names the rows whose verdicts the batch may have moved", context do
      project = create!(PolicyModule17, public: true)
      other_project = create!(PolicyModule17, public: true)
      label = create!(PolicyModule19)

      :ok = EntityOperations.add_relationship(PolicyModule17, project.id, :labels, label.id)

      effects = [
        effect(:patch_entity, PolicyModule19, label.id, %{"name" => "locked"}),
        effect(:patch_entity, PolicyModule17, other_project.id, %{"name" => "renamed"})
      ]

      parts = parts(effects, context.sessions, context.edges, @synced, @place)
      part = Map.fetch!(parts, nil)

      assert unpacked(part.verdict_ids) == %{PolicyModule17 => ids([project, other_project])}
      assert unpacked(part.checked)[PolicyModule17] == ids([project, other_project])
    end

    test "names the types a grant moved every row of, for its holder alone", context do
      edges = %{{PolicyModule1, :read} => [{:own_grants, [:viewer]}]}
      user = DB.read(Module14, context.alice)

      before = Oplog.read_type_after(RoleGrant, 0, 0, %{})
      Auth.grant_role(user, :viewer, PolicyModule1)

      effects =
        RoleGrant
        |> Oplog.read_type_after(0, 0, %{})
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

    test "names a pair's ends among the rows whose verdicts the batch may have moved", context do
      project = create!(PolicyModule17, public: true)
      label = create!(PolicyModule19)

      effects = [pair_effect(:add_relationship, project, :labels, label)]

      parts = parts(effects, context.sessions, context.edges, @synced, @place)
      part = Map.fetch!(parts, nil)

      assert unpacked(part.verdict_ids) == %{PolicyModule17 => ids([project])}
    end

    test "leaves out of the verdicts a type sync doesn't send", context do
      project = create!(PolicyModule17, public: true)
      effects = [effect(:patch_entity, PolicyModule17, project.id, %{"name" => "renamed"})]

      parts = parts(effects, context.sessions, context.edges, [PolicyModule18], @place)
      part = Map.fetch!(parts, nil)

      assert part.verdict_ids == %{}
    end

    test "passes over an effect whose type names a module that is no entity", context do
      effects = [effect(:patch_entity, String, Ecto.UUID.generate(), %{"a" => 1})]

      parts = parts(effects, context.sessions, context.edges, @synced, @place)
      part = Map.fetch!(parts, nil)

      assert part.checked == %{}
      assert part.pair_effects == %{}
      assert part.verdict_ids == %{}
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

      assert part.written == %{project.id => MapSet.new(["name", "public"])}
    end

    test "names what was written of the rows the user may read alone", context do
      project = create!(PolicyModule17)
      create!(PolicyModule18, project_id: project.id, user_id: context.alice)

      effects = [effect(:patch_entity, PolicyModule17, project.id, %{"name" => "renamed"})]

      parts = parts(effects, context.sessions, context.edges, @synced, @place)

      assert parts[context.alice].written == %{project.id => MapSet.new(["name"])}
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

  describe "route/2" do
    setup do
      setup_query_cache(QueryCacheStub, false)

      :persistent_term.put(QueryCacheStub.persistent_term_key(), %{
        entries: %{},
        synced_types: @synced,
        windows: %{@project_window => Stage.normalize(PolicyModule17)}
      })

      wait_for_process_cleanup(ResultStore)
      start_supervised!(ResultStore)

      wait_for_process_cleanup(Evaluator.registry())
      start_supervised!({Registry, keys: :unique, name: Evaluator.registry()})

      wait_for_process_cleanup(Evaluators)
      start_supervised!(Evaluators)

      wait_for_process_cleanup(Sessions.registry())
      start_supervised!(Sessions)

      :ok
    end

    test "sends nothing on a node with no session" do
      project = create!(PolicyModule17, public: true)
      effect = effect(:patch_entity, PolicyModule17, project.id, %{"name" => "renamed"})

      assert route([{100, [effect]}], @place) == :ok

      refute_received {:live, _part}
    end

    test "sends each session its user's part", context do
      project = create!(PolicyModule17)
      create!(PolicyModule18, project_id: project.id, user_id: context.alice)

      effect = effect(:patch_entity, PolicyModule17, project.id, %{"name" => "renamed"})

      Sessions.register(context.alice)
      start_forwarding_session(context.bob)

      assert route([{100, [effect]}], @place) == :ok

      assert_received {:live, part}
      assert part.place == @place
      assert Map.keys(part.readable[PolicyModule17]) == [project.id]

      assert_receive {:forwarded, {:live, bob_part}}
      assert bob_part.readable[PolicyModule17] == %{}

      refute_received {:live, _part}
    end

    test "hands the batch to the windows it could have changed too" do
      project = create!(PolicyModule17, public: true)
      effect = effect(:patch_entity, PolicyModule17, project.id, %{"name" => "renamed"})

      {:ok, evaluator, _version, _term} = Evaluators.subscribe(@project_window, self())
      DBConnection.Ownership.ownership_allow(DB.pool_name(), self(), evaluator, [])

      route([{100, [effect]}], @place)

      assert_receive {:round, @project_window, 1, _transactions, _place}
    end
  end
end
