defmodule Hologram.Sync.RecheckTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.DB.EntityOperations, only: [add_relationship: 4]
  import Hologram.Sync.Recheck
  import Hologram.Test.Stubs
  import Mox

  alias Hologram.Auth
  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.Policy
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyModule1
  alias Hologram.Test.Fixtures.Policy.Module13, as: PolicyModule13
  alias Hologram.Test.Fixtures.Policy.Module17, as: PolicyModule17
  alias Hologram.Test.Fixtures.Policy.Module19, as: PolicyModule19
  alias Hologram.Test.Fixtures.Policy.Module2, as: PolicyModule2
  alias Hologram.Test.Fixtures.Policy.Module3, as: PolicyModule3
  alias Hologram.Test.Fixtures.Policy.Module46, as: PolicyModule46
  alias Hologram.Test.Fixtures.Policy.Module47, as: PolicyModule47
  alias Hologram.Test.Fixtures.Policy.Module48, as: PolicyModule48
  alias Hologram.Test.Fixtures.Policy.Module49, as: PolicyModule49
  alias Hologram.Test.Fixtures.Policy.Module5, as: PolicyModule5
  alias Hologram.Test.Fixtures.Policy.Module6, as: PolicyModule6
  alias Hologram.Test.Fixtures.Policy.Module8, as: PolicyModule8
  alias Hologram.Test.Fixtures.Policy.Readers.Module1
  alias Hologram.Test.Fixtures.Policy.Readers.Module10
  alias Hologram.Test.Fixtures.Policy.Readers.Module11
  alias Hologram.Test.Fixtures.Policy.Readers.Module12
  alias Hologram.Test.Fixtures.Policy.Readers.Module13
  alias Hologram.Test.Fixtures.Policy.Readers.Module14, as: ReadersModule14
  alias Hologram.Test.Fixtures.Policy.Readers.Module15
  alias Hologram.Test.Fixtures.Policy.Readers.Module16
  alias Hologram.Test.Fixtures.Policy.Readers.Module17
  alias Hologram.Test.Fixtures.Policy.Readers.Module18
  alias Hologram.Test.Fixtures.Policy.Readers.Module19
  alias Hologram.Test.Fixtures.Policy.Readers.Module2
  alias Hologram.Test.Fixtures.Policy.Readers.Module20
  alias Hologram.Test.Fixtures.Policy.Readers.Module21
  alias Hologram.Test.Fixtures.Policy.Readers.Module22
  alias Hologram.Test.Fixtures.Policy.Readers.Module23
  alias Hologram.Test.Fixtures.Policy.Readers.Module24
  alias Hologram.Test.Fixtures.Policy.Readers.Module25
  alias Hologram.Test.Fixtures.Policy.Readers.Module28
  alias Hologram.Test.Fixtures.Policy.Readers.Module29
  alias Hologram.Test.Fixtures.Policy.Readers.Module3
  alias Hologram.Test.Fixtures.Policy.Readers.Module30
  alias Hologram.Test.Fixtures.Policy.Readers.Module31
  alias Hologram.Test.Fixtures.Policy.Readers.Module32
  alias Hologram.Test.Fixtures.Policy.Readers.Module33
  alias Hologram.Test.Fixtures.Policy.Readers.Module4
  alias Hologram.Test.Fixtures.Policy.Readers.Module5
  alias Hologram.Test.Fixtures.Policy.Readers.Module6
  alias Hologram.Test.Fixtures.Policy.Readers.Module7
  alias Hologram.Test.Fixtures.Policy.Readers.Module8
  alias Hologram.Test.Fixtures.Policy.Readers.Module9
  alias Hologram.Test.Fixtures.Role

  use_module_stub :query_cache

  # A build with a page checking permissions on the client - the only kind whose rows carry
  # verdicts. A test turning it off puts the flag again.
  setup do
    stub_with(QueryCacheMock, QueryCacheStub)
    :persistent_term.put(QueryCacheStub.persistent_term_key(), %{permission_checking?: true})

    on_exit(fn -> :persistent_term.erase(QueryCacheStub.persistent_term_key()) end)
  end

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
          {:ok, {_row, readers, _verdicts}} -> reads?(readers, user_id)
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
    {_row, readers, _verdicts} = Map.fetch!(readable, row.id)

    readers
  end

  # Every reader's verdicts are what Auth.verdicts/2 answers for the row the recheck read, one row
  # and one user at a time - for every row given, each readable by somebody, and every user given
  # who may read it, anonymous ones included.
  defp assert_verdicts_as_auth(entity_type, rows, user_ids) do
    assert Policy.verdict_operations(entity_type) != []

    readable =
      %{entity_type => Enum.map(rows, & &1.id)}
      |> run(user_ids)
      |> Map.get(entity_type, %{})

    readable_ids =
      readable
      |> Map.keys()
      |> MapSet.new()

    assert readable_ids == MapSet.new(rows, & &1.id)

    for {_id, {row, readers, row_verdicts}} <- readable,
        user_id <- user_ids,
        reads?(readers, user_id) do
      assert verdicts(row_verdicts, user_id) == Auth.verdicts(user_id, row),
             "#{inspect(entity_type)} row #{row.id}, user #{inspect(user_id)}"
    end

    readable
  end

  defp verdicts_of(readable, row) do
    {_row, _readers, row_verdicts} = Map.fetch!(readable, row.id)

    row_verdicts
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

      %{Module1 => %{^project_id => {_row, readers, _verdicts}}} =
        run(%{Module1 => [project.id]}, context.users)

      assert readers == MapSet.new([context.alice])
    end

    test "leaves out a reader found from the row who isn't among the given users", context do
      project = create(Module1)
      project_id = project.id

      create(Module2, %{project_id: project.id, user_id: context.alice})
      create(Module2, %{project_id: project.id, user_id: context.bob})

      %{Module1 => %{^project_id => {_row, readers, _verdicts}}} =
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

    test "admits a role held on the whole type to the grants on a row, not to a type-wide grant",
         context do
      entity = create(PolicyModule2)

      Auth.grant_role(context.alice, :member, PolicyModule2)
      Auth.grant_role(context.bob, :member, entity)
      Auth.grant_role(context.carol, :member, PolicyModule2)

      grants = DB.read(RoleGrant)
      readable = assert_answers_as_can(RoleGrant, grants, context.users)

      bob_grant = Enum.find(grants, &(&1.user_id == context.bob))
      alice_grant = Enum.find(grants, &(&1.user_id == context.alice))

      assert readers_of(readable, bob_grant) ==
               MapSet.new([context.alice, context.bob, context.carol])

      assert readers_of(readable, alice_grant) == MapSet.new([context.alice])
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

      %{Module1 => %{^project_id => {row, _readers, _verdicts}}} =
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

      shared_id = shared.id

      assert %{PolicyModule6 => %{^shared_id => {row, :all, _verdicts}} = readable} =
               run(%{PolicyModule6 => [shared.id, authored.id]}, [nil])

      assert row == DB.read(PolicyModule6, shared.id)
      assert map_size(readable) == 1
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

      {_row, owned_readers, _verdicts} = readable[Module5][owned.id]
      {_row, shared_readers, _verdicts} = readable[PolicyModule6][shared.id]

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

      %{Module1 => %{^project_id => {_row, readers, _verdicts}}} =
        run(%{Module1 => [project.id]}, [context.alice, context.alice])

      assert readers == MapSet.new([context.alice])
    end
  end

  describe "run/2 verdicts" do
    # A board everyone reads, with a card alice wrote and a done one bob reviews, and an empty one.
    defp boards(context) do
      board = create(Module15)
      empty = create(Module15)

      create(Module16, %{author_id: context.alice, board_id: board.id})
      create(Module16, %{board_id: board.id, done: true, reviewer_id: context.bob})

      {board, empty}
    end

    test "answers each reader's verdicts on a row everyone may read as Auth.verdicts/2 does",
         context do
      {board, empty} = boards(context)

      assert_verdicts_as_auth(Module15, [board, empty], context.users)
    end

    # The close rule's any is bounded by the open cards' authors: Alice wrote the open card, and
    # Bob's card is done.
    test "answers a listed operation for the users its anchor names among the readers", context do
      {board, _empty} = boards(context)

      readable = assert_verdicts_as_auth(Module15, [board], context.users)
      row_verdicts = verdicts_of(readable, board)
      close_key = Policy.verdict_key(Module15, :close)

      assert verdicts(row_verdicts, context.alice)[close_key] == true
      assert verdicts(row_verdicts, context.bob)[close_key] == false
      assert verdicts(row_verdicts, context.carol)[close_key] == false
      assert row_verdicts.others[close_key] == false
    end

    test "answers an operation whose rules name nobody once per row", context do
      {board, empty} = boards(context)

      readable = run(%{Module15 => [board.id, empty.id]}, context.users)
      delete_key = Policy.verdict_key(Module15, :delete)

      for {row, expected} <- [{board, false}, {empty, true}], user_id <- context.users do
        assert verdicts(verdicts_of(readable[Module15], row), user_id)[delete_key] == expected
      end
    end

    # Alice wrote the open card, so the share rule admits her, and the close rule admits Bob, who
    # didn't. Carol wrote no card, so she can't read the holder and is never tested.
    test "tests only the readers on a type with unlisted operations", context do
      holder = create(Module17)
      create(Module16, %{author_id: context.alice, holder_id: holder.id})
      create(Module16, %{author_id: context.bob, done: true, holder_id: holder.id})

      readable = assert_verdicts_as_auth(Module17, [holder], context.users)
      row_verdicts = verdicts_of(readable, holder)

      admitted_ids =
        row_verdicts.users
        |> Map.keys()
        |> MapSet.new()

      assert admitted_ids == MapSet.new([context.alice, context.bob])
      assert verdicts(row_verdicts, context.alice)[Policy.verdict_key(Module17, :share)] == true
      assert verdicts(row_verdicts, context.bob)[Policy.verdict_key(Module17, :close)] == true
    end

    # Carol reviews Alice's open card, so the claim rule names her, but she wrote no card and can't
    # read the holder - only the readers among the users an anchor names are tested.
    test "tests the readers among the users a listed operation's anchor names", context do
      holder = create(Module17)

      create(Module16, %{
        author_id: context.alice,
        holder_id: holder.id,
        reviewer_id: context.carol
      })

      create(Module16, %{
        author_id: context.bob,
        holder_id: holder.id,
        reviewer_id: context.alice
      })

      readable = assert_verdicts_as_auth(Module17, [holder], context.users)
      {_row, readers, row_verdicts} = readable[holder.id]
      claim_key = Policy.verdict_key(Module17, :claim)

      assert readers == MapSet.new([context.alice, context.bob])
      refute Map.has_key?(row_verdicts.users, context.carol)
      assert verdicts(row_verdicts, context.alice)[claim_key] == true
      assert verdicts(row_verdicts, context.bob)[claim_key] == false
    end

    # Each type's only deciding items are in its read rules: a none naming the user, server-only
    # values on the row and through a path, and paths, a role reference and delegations through a
    # type nobody may read. The read verdict is all a reader is told.
    test "answers the read verdict alone for types whose read rules alone are deciding",
         context do
      subject = create(Module6)
      create(Module7, %{subject_id: subject.id, user_id: context.alice})

      reviewed = create(Module18, %{reviewed: true, steward_id: context.bob})
      stewarded = create(Module18, %{steward_id: context.alice})
      note = create(Module19, %{report_id: reviewed.id})

      project = create(Module20, %{steward_id: context.bob})
      task = create(Module21, %{project_id: project.id})

      team = create(Module22, %{})
      team_project = create(Module23, %{team_id: team.id})
      team_task = create(Module24, %{project_id: team_project.id})
      Auth.grant_role(context.alice, :member, team)

      vault = create(Module25, %{keeper_id: context.alice, open: true})
      parcel = create(Module28, %{vault_id: vault.id})
      Auth.grant_role(context.alice, :member, vault)

      rows = [
        {Module6, [subject]},
        {Module18, [reviewed, stewarded]},
        {Module19, [note]},
        {Module21, [task]},
        {Module24, [team_task]},
        {Module28, [parcel]}
      ]

      for {entity_type, type_rows} <- rows do
        readable = assert_verdicts_as_auth(entity_type, type_rows, context.users)
        read_key = Policy.verdict_key(entity_type, :read)

        for {_id, {_row, readers, row_verdicts}} <- readable,
            user_id <- context.users,
            reads?(readers, user_id) do
          assert verdicts(row_verdicts, user_id) == %{read_key => true}
        end
      end
    end

    # Alice keeps the vault, Carol holds a role on it, and Bob reads the open parcel by its own
    # rule. Each reads it for another reason, and none is told which: the read verdict is all there
    # is.
    test "answers the read verdict true for every reader, whatever admits them", context do
      vault = create(Module25, %{keeper_id: context.alice})
      parcel = create(Module29, %{open: true, vault_id: vault.id})

      Auth.grant_role(context.carol, :member, vault)

      readable = assert_verdicts_as_auth(Module29, [parcel], context.users)
      row_verdicts = verdicts_of(readable, parcel)
      read_key = Policy.verdict_key(Module29, :read)

      assert row_verdicts.users == %{}

      for user_id <- context.users do
        assert verdicts(row_verdicts, user_id) == %{read_key => true}
      end
    end

    test "answers clauses over paths and through related sets for every user alike", context do
      project = create(PolicyModule17, %{public: true})
      locked = create(PolicyModule19, %{name: "locked"})
      add_relationship(PolicyModule17, project.id, :labels, locked.id)

      assert_verdicts_as_auth(
        PolicyModule17,
        [project, create(PolicyModule17, %{public: true})],
        context.users
      )
    end

    # Each tool's lines read a workshop through a delegation to the tool's workshop's update rule
    # and through a role held on its bench's workshop, a different one, beside a none over its
    # pegs, which a loose peg refutes. Alice edits the bench's workshop and Bob the tool's, and
    # Carol owns the bench's workshop: reading either path through the other's workshop flips an
    # answer.
    test "answers a delegation and a role reference through a path in a non-read operation",
         context do
      tool_workshop = create(Module30)
      bench_workshop = create(Module30)
      bench = create(Module31, %{workshop_id: bench_workshop.id})
      tool = create(Module32, %{bench_id: bench.id, workshop_id: tool_workshop.id})
      loose_tool = create(Module32, %{bench_id: bench.id, workshop_id: tool_workshop.id})
      create(Module33, %{loose: true, tool_id: loose_tool.id})

      Auth.grant_role(context.alice, :editor, bench_workshop)
      Auth.grant_role(context.bob, :editor, tool_workshop)
      Auth.grant_role(context.carol, :owner, bench_workshop)

      readable = assert_verdicts_as_auth(Module32, [tool, loose_tool], context.users)
      delete_key = Policy.verdict_key(Module32, :delete)
      label_key = Policy.verdict_key(Module32, {:update, :label})

      expected = %{
        context.alice => %{delete_key => false, label_key => true},
        context.bob => %{delete_key => true, label_key => false},
        context.carol => %{delete_key => false, label_key => false},
        nil => %{delete_key => false, label_key => false}
      }

      for user_id <- context.users do
        assert verdicts(verdicts_of(readable, tool), user_id) == expected[user_id]

        assert verdicts(verdicts_of(readable, loose_tool), user_id) ==
                 %{delete_key => false, label_key => false}
      end
    end

    # Only a workshop's owner and members read it, its benches and its tools' permits, so the
    # server answers every operation of a tool reading one: one tool has an approved permit and the
    # other an unapproved one, and Alice edits the bench's workshop.
    test "answers the operations reading related rows a reader may not hold", context do
      workshop = create(PolicyModule46, %{archived: true})
      bench = create(PolicyModule47, %{workshop_id: workshop.id})
      approved = create(PolicyModule49, %{bench_id: bench.id, workshop_id: workshop.id})
      unapproved = create(PolicyModule49, %{bench_id: bench.id, workshop_id: workshop.id})
      create(PolicyModule48, %{approved: true, tool_id: approved.id})
      create(PolicyModule48, %{tool_id: unapproved.id})

      Auth.grant_role(context.alice, :editor, workshop)

      readable = assert_verdicts_as_auth(PolicyModule49, [approved, unapproved], context.users)
      bench_key = Policy.verdict_key(PolicyModule49, {:update, :bench})
      delete_key = Policy.verdict_key(PolicyModule49, :delete)

      for user_id <- context.users do
        assert verdicts(verdicts_of(readable, approved), user_id)[bench_key] == true
        assert verdicts(verdicts_of(readable, unapproved), user_id)[bench_key] == false
      end

      assert verdicts(verdicts_of(readable, approved), context.alice)[delete_key] == true
      assert verdicts(verdicts_of(readable, approved), context.bob)[delete_key] == false
    end

    test "answers no anonymous user when none was given", context do
      {board, _empty} = boards(context)

      readable = assert_verdicts_as_auth(Module15, [board], [context.alice, context.bob])

      assert verdicts_of(readable, board).anonymous == nil
    end

    test "answers no verdicts when no client checks permissions", context do
      :persistent_term.put(QueryCacheStub.persistent_term_key(), %{permission_checking?: false})

      {board, _empty} = boards(context)

      row_verdicts =
        %{Module15 => [board.id]}
        |> run(context.users)
        |> Map.fetch!(Module15)
        |> verdicts_of(board)

      for user_id <- context.users do
        assert verdicts(row_verdicts, user_id) == %{}
      end
    end

    test "answers no verdicts for a type the server sends none on", context do
      membership = create(Module2, %{user_id: context.alice})

      readable = run(%{Module2 => [membership.id]}, context.users)

      assert verdicts(verdicts_of(readable[Module2], membership), context.alice) == %{}
    end

    # Nothing to answer, so whether a client checks permissions is never asked - the query cache is
    # never read, as Frame.row_verdicts/2 leaves it.
    test "never asks whether a client checks permissions when no type has verdicts",
         context do
      :persistent_term.erase(QueryCacheStub.persistent_term_key())

      membership = create(Module2, %{user_id: context.alice})

      readable = run(%{Module2 => [membership.id]}, context.users)

      assert verdicts(verdicts_of(readable[Module2], membership), context.alice) == %{}
    end

    test "answers a user id in another spelling as an anonymous user", context do
      {board, _empty} = boards(context)

      shouted = String.upcase(context.alice)
      readable = run(%{Module15 => [board.id]}, [shouted, context.bob])
      row_verdicts = verdicts_of(readable[Module15], board)

      assert verdicts(row_verdicts, shouted) == Auth.verdicts(nil, board)
      assert verdicts(row_verdicts, shouted) == verdicts(row_verdicts, nil)
    end
  end

  @alice_id "018f4571-a1b2-7c3d-8e4f-000000000001"
  @bob_id "018f4571-a1b2-7c3d-8e4f-000000000002"

  describe "verdicts/2" do
    @row_verdicts %{
      anonymous: %{"archive:a" => false},
      others: %{"archive:a" => true},
      users: %{@alice_id => %{"archive:a" => false}}
    }

    test "answers a reader an operation admits from their own answers" do
      assert verdicts(@row_verdicts, @alice_id) == %{"archive:a" => false}
    end

    test "answers any other reader with the others' answers" do
      assert verdicts(@row_verdicts, @bob_id) == %{"archive:a" => true}
    end

    test "answers an anonymous user, and a user id in another spelling, as anonymous" do
      assert verdicts(@row_verdicts, nil) == %{"archive:a" => false}
      assert verdicts(@row_verdicts, String.upcase(@bob_id)) == %{"archive:a" => false}
    end

    test "raises for an anonymous user when none was given" do
      assert_raise ArgumentError, fn -> verdicts(%{@row_verdicts | anonymous: nil}, nil) end
    end
  end

  describe "verdicts_as_canonical/2" do
    test "answers a reader an operation admits, any other reader, and an anonymous user" do
      assert verdicts_as_canonical(@row_verdicts, @alice_id) == %{"archive:a" => false}
      assert verdicts_as_canonical(@row_verdicts, @bob_id) == %{"archive:a" => true}
      assert verdicts_as_canonical(@row_verdicts, nil) == %{"archive:a" => false}
    end

    test "raises for an anonymous user when none was given" do
      assert_raise ArgumentError, fn ->
        verdicts_as_canonical(%{@row_verdicts | anonymous: nil}, nil)
      end
    end
  end

  describe "reads?/2" do
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

  describe "reads_as_canonical?/2" do
    test "every user reads a row everyone may read" do
      assert reads_as_canonical?(:all, @alice_id)
      assert reads_as_canonical?(:all, nil)
    end

    test "a user reads a row when the readers name them" do
      readers = MapSet.new([@alice_id, nil])

      assert reads_as_canonical?(readers, @alice_id)
      assert reads_as_canonical?(readers, nil)
      refute reads_as_canonical?(readers, @bob_id)
    end
  end
end
