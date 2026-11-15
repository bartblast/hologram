defmodule Hologram.Sync.RecheckTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.DB.EntityOperations, only: [add_relationship: 4]
  import Hologram.Sync.Recheck

  alias Hologram.Auth
  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyModule1
  alias Hologram.Test.Fixtures.Policy.Module13, as: PolicyModule13
  alias Hologram.Test.Fixtures.Policy.Module2, as: PolicyModule2
  alias Hologram.Test.Fixtures.Policy.Module3, as: PolicyModule3
  alias Hologram.Test.Fixtures.Policy.Module5, as: PolicyModule5
  alias Hologram.Test.Fixtures.Policy.Module6, as: PolicyModule6
  alias Hologram.Test.Fixtures.Policy.Module8, as: PolicyModule8
  alias Hologram.Test.Fixtures.Policy.Readers.Module1
  alias Hologram.Test.Fixtures.Policy.Readers.Module10
  alias Hologram.Test.Fixtures.Policy.Readers.Module11
  alias Hologram.Test.Fixtures.Policy.Readers.Module12
  alias Hologram.Test.Fixtures.Policy.Readers.Module13
  alias Hologram.Test.Fixtures.Policy.Readers.Module14, as: ReadersModule14
  alias Hologram.Test.Fixtures.Policy.Readers.Module2
  alias Hologram.Test.Fixtures.Policy.Readers.Module3
  alias Hologram.Test.Fixtures.Policy.Readers.Module4
  alias Hologram.Test.Fixtures.Policy.Readers.Module5
  alias Hologram.Test.Fixtures.Policy.Readers.Module6
  alias Hologram.Test.Fixtures.Policy.Readers.Module7
  alias Hologram.Test.Fixtures.Policy.Readers.Module8
  alias Hologram.Test.Fixtures.Policy.Readers.Module9
  alias Hologram.Test.Fixtures.Role

  setup do
    alice = create_user("alice@example.com")
    bob = create_user("bob@example.com")
    carol = create_user("carol@example.com")

    %{alice: alice.id, bob: bob.id, carol: carol.id, users: [alice.id, bob.id, carol.id, nil]}
  end

  # The recheck answers what Auth.can?/3 answers, one row and one user at a time - for every row
  # and every user given, anonymous ones included.
  defp assert_answers_as_can(entity_type, rows, user_ids) do
    readable =
      %{entity_type => Enum.map(rows, & &1.id)}
      |> run(user_ids)
      |> Map.get(entity_type, %{})

    for row <- rows, user_id <- user_ids do
      expected = Auth.can?(user_id, :read, row)

      actual =
        case Map.fetch(readable, row.id) do
          {:ok, {_row, readers}} -> reads?(readers, user_id)
          :error -> false
        end

      assert actual == expected,
             "#{inspect(entity_type)} row #{row.id}, user #{inspect(user_id)}: " <>
               "expected #{expected}, got #{actual}"
    end

    readable
  end

  defp create(entity_type, values \\ %{}) do
    values
    |> entity_type.new()
    |> DB.create!()
  end

  defp create_user(email), do: create(Module14, %{email: email})

  defp readers_of(readable, row) do
    {_row, readers} = Map.fetch!(readable, row.id)

    readers
  end

  describe "run/2" do
    test "lists the members of a row's set as its readers", context do
      project_p = create(Module1)
      project_q = create(Module1)
      create(Module1)

      create(Module2, %{project_id: project_p.id, user_id: context.alice})
      create(Module2, %{project_id: project_p.id, user_id: context.bob})
      create(Module2, %{project_id: project_q.id, user_id: context.bob})

      projects = DB.read(Module1)
      readable = assert_answers_as_can(Module1, projects, context.users)

      assert readers_of(readable, project_p) == MapSet.new([context.alice, context.bob])
      assert readers_of(readable, project_q) == MapSet.new([context.bob])
      assert map_size(readable) == 2
    end

    test "lists a reader the row reaches twice once", context do
      project = create(Module1)
      project_id = project.id

      create(Module2, %{project_id: project.id, user_id: context.alice})
      create(Module2, %{project_id: project.id, user_id: context.alice})

      %{Module1 => %{^project_id => {_row, readers}}} =
        run(%{Module1 => [project.id]}, context.users)

      assert readers == MapSet.new([context.alice])
    end

    test "leaves out a reader found from the row who isn't among the given users", context do
      project = create(Module1)
      project_id = project.id

      create(Module2, %{project_id: project.id, user_id: context.alice})
      create(Module2, %{project_id: project.id, user_id: context.bob})

      %{Module1 => %{^project_id => {_row, readers}}} =
        run(%{Module1 => [project.id]}, [context.bob, nil])

      assert readers == MapSet.new([context.bob])
    end

    test "decides a row's own membership by the user it names", context do
      project = create(Module1)
      membership = create(Module2, %{project_id: project.id, user_id: context.alice})
      orphan = create(Module2)

      readable = assert_answers_as_can(Module2, [membership, orphan], context.users)

      assert readers_of(readable, membership) == MapSet.new([context.alice])
      refute Map.has_key?(readable, orphan.id)
    end

    test "follows a path to the set and a delegation to the related row", context do
      project = create(Module1)
      create(Module2, %{project_id: project.id, user_id: context.carol})

      milestones = [create(Module3, %{project_id: project.id}), create(Module3)]
      notes = [create(Module4, %{project_id: project.id}), create(Module4)]

      assert_answers_as_can(Module3, milestones, context.users)
      assert_answers_as_can(Module4, notes, context.users)
    end

    test "tests every user for a rule that denies one", context do
      owned = [create(Module5, %{owner_id: context.alice}), create(Module5)]

      readable = assert_answers_as_can(Module5, owned, context.users)

      assert readers_of(readable, hd(owned)) == MapSet.new([context.bob, context.carol])

      assert_answers_as_can(
        Module11,
        [create(Module11, %{owned_id: hd(owned).id})],
        context.users
      )
    end

    test "tests every user for the acting user named only inside a none", context do
      blocked = create(Module6)
      create(Module7, %{subject_id: blocked.id, user_id: context.bob})
      open = create(Module6)

      readable = assert_answers_as_can(Module6, [blocked, open], context.users)

      assert readers_of(readable, blocked) == MapSet.new([context.alice, context.carol])
    end

    test "decides nested, flattened and outer-row quantifiers and split disjunctions", context do
      owned_closed = create(Module8, %{archived: true, owner_id: context.alice})
      open_board = create(Module8, %{open: true})
      archived_open = create(Module8, %{archived: true, open: true})
      listed = create(Module8, %{archived: true})

      list = create(Module9, %{board_id: listed.id, deputy_id: context.bob, open: true})
      create(Module10, %{assignee_id: context.carol, list_id: list.id})
      create(Module10, %{list_id: list.id, reviewer_id: context.alice})

      create(Module9, %{board_id: owned_closed.id, open: true})

      sponsored = create(Module8, %{archived: true, sponsor_id: context.bob})
      watched = create(Module8, %{archived: true})
      watched_list = create(Module9, %{board_id: watched.id})
      create(Module10, %{list_id: watched_list.id, watcher_id: context.carol})
      create(Module10, %{done: true, list_id: watched_list.id, watcher_id: context.alice})

      boards = [owned_closed, open_board, archived_open, listed, sponsored, watched]
      readable = assert_answers_as_can(Module8, boards, context.users)

      assert readers_of(readable, sponsored) == MapSet.new([context.bob])
      assert readers_of(readable, watched) == MapSet.new([context.carol])

      assert readers_of(readable, open_board) == :all

      assert readers_of(readable, listed) ==
               MapSet.new([context.alice, context.bob, context.carol])
    end

    test "decides the quantifiers, disjunctions and inequalities of one type together", context do
      list = create(Module9, %{lead_id: context.bob})
      board = create(Module12, %{archived: true})
      empty_board = create(Module12, %{archived: true})
      add_relationship(Module12, board.id, :lists, list.id)

      assert_answers_as_can(Module12, [board, empty_board], context.users)
    end

    test "decides grants, delegations of another operation and split delegations", context do
      %{alice: alice, bob: bob, carol: carol} = context

      led_list = create(Module9, %{lead_id: bob})
      open_list = create(Module9, %{open: true})
      deputy_list = create(Module9, %{deputy_id: carol})
      public_parent = create(PolicyModule1, %{public: true})
      private_parent = create(PolicyModule1)

      granted = create(Module13, %{open: true})
      by_list = create(Module13, %{list_id: led_list.id})
      under_public = create(Module13, %{owner_id: carol, parent_id: public_parent.id})
      under_private = create(Module13, %{owner_id: carol, parent_id: private_parent.id})
      ungranted_parent = create(Module13, %{owner_id: bob, parent_id: private_parent.id})
      viewer_led = create(Module13, %{other_list_id: led_list.id})
      ungranted_led = create(Module13, %{other_list_id: led_list.id})
      viewer_owned = create(Module13, %{owner_id: alice})
      outer = create(Module13, %{owner_id: alice})
      deputy = create(Module13)
      grandparent = create(PolicyModule2)
      chained_parent = create(PolicyModule1, %{parent_id: grandparent.id})
      two_hops = create(Module13, %{parent_id: chained_parent.id})

      add_relationship(Module13, outer.id, :lists, open_list.id)
      add_relationship(Module13, deputy.id, :lists, deputy_list.id)
      add_relationship(Module13, deputy.id, :lists, led_list.id)

      Auth.grant_role(alice, :viewer, granted)
      Auth.grant_role(alice, :viewer, by_list)
      Auth.grant_role(carol, :viewer, private_parent)
      Auth.grant_role(bob, :viewer, viewer_led)
      Auth.grant_role(alice, :viewer, viewer_owned)
      Auth.grant_role(bob, :viewer, viewer_owned)
      Auth.grant_role(bob, :admin, grandparent)
      Auth.grant_role(alice, :member, grandparent)

      rows = [
        granted,
        by_list,
        under_public,
        under_private,
        ungranted_parent,
        viewer_led,
        ungranted_led,
        viewer_owned,
        outer,
        deputy,
        two_hops
      ]

      readable = assert_answers_as_can(Module13, rows, context.users)

      assert readers_of(readable, granted) == MapSet.new([alice])
      assert readers_of(readable, by_list) == MapSet.new([bob])
      assert readers_of(readable, under_public) == MapSet.new([carol])
      assert readers_of(readable, under_private) == MapSet.new([carol])
      refute Map.has_key?(readable, ungranted_parent.id)
      assert readers_of(readable, viewer_led) == MapSet.new([bob])
      refute Map.has_key?(readable, ungranted_led.id)
      assert readers_of(readable, viewer_owned) == MapSet.new([alice])
      assert readers_of(readable, outer) == MapSet.new([alice])
      assert readers_of(readable, deputy) == MapSet.new([bob, carol])
      assert readers_of(readable, two_hops) == MapSet.new([alice, bob])
    end

    test "decides grant and delegation rules of the policy fixtures", context do
      public_child = create(PolicyModule1, %{public: true})
      viewed_child = create(PolicyModule1)
      admin_parent = create(PolicyModule2)

      Auth.grant_role(context.bob, :viewer, viewed_child)
      Auth.grant_role(context.alice, :admin, PolicyModule2)
      Auth.grant_role(context.carol, :viewer, PolicyModule1)

      children = [
        public_child,
        viewed_child,
        create(PolicyModule1, %{parent_id: admin_parent.id})
      ]

      readable = assert_answers_as_can(PolicyModule1, children, context.users)

      assert readers_of(readable, public_child) == :all

      assert readers_of(readable, viewed_child) ==
               MapSet.new([context.alice, context.bob, context.carol])

      delegators = Enum.map(children, &create(PolicyModule5, %{parent_id: &1.id}))
      assert_answers_as_can(PolicyModule5, delegators, context.users)

      delegators_twice = Enum.map(delegators, &create(PolicyModule8, %{parent_id: &1.id}))
      assert_answers_as_can(PolicyModule8, delegators_twice, context.users)
    end

    test "finds the holders of a role on a related row", context do
      parent = create(PolicyModule2)
      other_parent = create(PolicyModule2)

      Auth.grant_role(context.alice, :member, parent)
      Auth.grant_role(context.bob, :member, other_parent)

      child = create(PolicyModule13, %{parent_id: parent.id})
      orphan = create(PolicyModule13)

      readable = assert_answers_as_can(PolicyModule13, [child, orphan], context.users)

      assert readers_of(readable, child) == MapSet.new([context.alice])
      refute Map.has_key?(readable, orphan.id)
    end

    test "decides the grant store's own rules", context do
      entity = create(PolicyModule2)

      Auth.grant_role(context.alice, :member, entity)
      Auth.grant_role(context.bob, :admin, entity)
      Auth.grant_role(context.carol, Role.Module1)

      grants = DB.read(RoleGrant)
      readable = assert_answers_as_can(RoleGrant, grants, context.users)

      bob_grant = Enum.find(grants, &(&1.user_id == context.bob))

      assert readers_of(readable, bob_grant) ==
               MapSet.new([context.alice, context.bob, context.carol])
    end

    test "decides a rule admitting everyone once for every user", context do
      container = create(PolicyModule3)

      readable = assert_answers_as_can(PolicyModule3, [container], context.users)

      assert readers_of(readable, container) == :all
    end

    test "admits anonymous users to the rows a rule naming nobody admits", context do
      shared = create(PolicyModule6, %{shared: true})
      authored = create(PolicyModule6, %{author_id: context.alice})

      readable = assert_answers_as_can(PolicyModule6, [shared, authored], context.users)

      assert readers_of(readable, shared) == :all
      assert readers_of(readable, authored) == MapSet.new([context.alice])
    end

    test "names an anonymous reader a delegated rule admits through its part naming nobody",
         context do
      open_list = create(Module9, %{open: true})
      board = create(Module12, %{archived: true})
      closed_board = create(Module12, %{archived: true})
      add_relationship(Module12, board.id, :lists, open_list.id)

      delegating = create(ReadersModule14, %{board_id: board.id})
      closed_delegating = create(ReadersModule14, %{board_id: closed_board.id})

      readable =
        assert_answers_as_can(ReadersModule14, [delegating, closed_delegating], context.users)

      assert nil in readers_of(readable, delegating)
    end

    test "names an anonymous reader when only the folded rules admit one", context do
      list = create(Module9, %{open: true})
      board = create(Module12, %{archived: true})
      add_relationship(Module12, board.id, :lists, list.id)

      readable = assert_answers_as_can(Module12, [board], context.users)

      assert nil in readers_of(readable, board)
    end

    test "leaves out a row none of the given users may read, and an id with no row", context do
      project = create(Module1)
      gone_id = Ecto.UUID.generate()

      assert run(%{Module1 => [project.id, gone_id]}, context.users) == %{Module1 => %{}}
    end

    test "returns the rows' current values", context do
      project = create(Module1, %{name: "Alpha"})
      create(Module2, %{project_id: project.id, user_id: context.alice})

      DB.update!(Module1, project.id, name: "Beta")

      project_id = project.id

      %{Module1 => %{^project_id => {row, _readers}}} =
        run(%{Module1 => [project.id]}, [context.alice])

      assert row == DB.read(Module1, project.id)
      assert row.name == "Beta"
    end

    test "decides several entity types in one call", context do
      project = create(Module1)
      membership = create(Module2, %{project_id: project.id, user_id: context.bob})

      result = run(%{Module1 => [project.id], Module2 => [membership.id]}, [context.bob])

      assert Map.keys(result) -- [Module1, Module2] == []
      assert map_size(result) == 2
      assert Map.keys(result[Module1]) == [project.id]
      assert Map.keys(result[Module2]) == [membership.id]
    end

    test "runs nothing for a type with no ids", context do
      assert run(%{Module1 => []}, context.users) == %{}
    end

    test "runs nothing for no users" do
      project = create(Module1)

      assert run(%{Module1 => [project.id]}, []) == %{}
    end

    test "decides anonymous users alone" do
      shared = create(PolicyModule6, %{shared: true})
      authored = create(PolicyModule6)

      assert run(%{PolicyModule6 => [shared.id, authored.id]}, [nil]) == %{
               PolicyModule6 => %{shared.id => {DB.read(PolicyModule6, shared.id), :all}}
             }
    end

    # A session's user id may be any string, integer or atom, and one naming no user entity is
    # anonymous to the rules, as Auth.can?/3 answers it.
    test "reads a user id in another spelling as an anonymous user, answering the rest",
         context do
      owned = create(Module5)
      shared = create(PolicyModule6, %{shared: true})
      authored = create(PolicyModule6, %{author_id: context.alice})

      shouted = String.upcase(context.alice)
      user_ids = [shouted, "not-a-uuid", context.alice <> "\n", 7, context.bob]

      readable =
        run(%{Module5 => [owned.id], PolicyModule6 => [shared.id, authored.id]}, user_ids)

      {_row, owned_readers} = readable[Module5][owned.id]
      {_row, shared_readers} = readable[PolicyModule6][shared.id]

      assert owned_readers == MapSet.new([context.bob])
      assert shared_readers == :all
      refute Map.has_key?(readable[PolicyModule6], authored.id)

      for user_id <- user_ids do
        assert reads?(owned_readers, user_id) == Auth.can?(user_id, :read, owned)
        assert reads?(shared_readers, user_id) == Auth.can?(user_id, :read, shared)
        refute Auth.can?(user_id, :read, authored)
      end
    end

    test "lists a user given twice once", context do
      project = create(Module1)
      project_id = project.id
      create(Module2, %{project_id: project.id, user_id: context.alice})

      %{Module1 => %{^project_id => {_row, readers}}} =
        run(%{Module1 => [project.id]}, [context.alice, context.alice])

      assert readers == MapSet.new([context.alice])
    end
  end

  describe "reads?/2" do
    @alice_id "018f4571-a1b2-7c3d-8e4f-000000000001"
    @bob_id "018f4571-a1b2-7c3d-8e4f-000000000002"

    test "every user reads a row everyone may read" do
      assert reads?(:all, @alice_id)
      assert reads?(:all, nil)
    end

    test "a user reads a row when the readers name them" do
      readers = MapSet.new([@alice_id])

      assert reads?(readers, @alice_id)
      refute reads?(readers, @bob_id)
      refute reads?(readers, nil)
    end

    test "an anonymous user reads a row when the readers name one" do
      readers = MapSet.new([nil])

      assert reads?(readers, nil)
      refute reads?(readers, @alice_id)
    end

    test "a user id in a spelling Hologram doesn't generate reads as an anonymous user" do
      assert reads?(MapSet.new([nil]), String.upcase(@alice_id))
      refute reads?(MapSet.new([@alice_id]), String.upcase(@alice_id))
    end
  end
end
