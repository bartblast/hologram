defmodule Hologram.DB.QueryRunnerTest do
  use Hologram.Test.DatabaseCase, async: true
  use Hologram.DB

  import Hologram.DB.EntityOperations, only: [add_relationship: 4, create: 1]
  import Hologram.DB.QueryRunner

  alias Hologram.Auth
  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.DB.QueryCompiler
  alias Hologram.Entity.NotIncluded
  alias Hologram.Policy
  alias Hologram.Query
  alias Hologram.Query.Placeholder
  alias Hologram.Query.Stage
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module10
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module22
  alias Hologram.Test.Fixtures.Entity.Module23
  alias Hologram.Test.Fixtures.Entity.Module26
  alias Hologram.Test.Fixtures.Entity.Module27
  alias Hologram.Test.Fixtures.Entity.Module28
  alias Hologram.Test.Fixtures.Entity.Module29
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module31
  alias Hologram.Test.Fixtures.Entity.Module32
  alias Hologram.Test.Fixtures.Entity.Module33
  alias Hologram.Test.Fixtures.Entity.Module34
  alias Hologram.Test.Fixtures.Entity.Module37
  alias Hologram.Test.Fixtures.Entity.Module38
  alias Hologram.Test.Fixtures.Entity.Module39
  alias Hologram.Test.Fixtures.Entity.Module4
  alias Hologram.Test.Fixtures.Entity.Module40
  alias Hologram.Test.Fixtures.Entity.Module41
  alias Hologram.Test.Fixtures.Entity.Module42
  alias Hologram.Test.Fixtures.Entity.Module8
  alias Hologram.Test.Fixtures.Entity.Module9
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyModule1
  alias Hologram.Test.Fixtures.Policy.Module17, as: PolicyModule17
  alias Hologram.Test.Fixtures.Policy.Module18, as: PolicyModule18
  alias Hologram.Test.Fixtures.Policy.Module19, as: PolicyModule19
  alias Hologram.Test.Fixtures.Policy.Module2, as: PolicyModule2
  alias Hologram.Test.Fixtures.Policy.Module20, as: PolicyModule20
  alias Hologram.Test.Fixtures.Policy.Module21, as: PolicyModule21
  alias Hologram.Test.Fixtures.Policy.Module22, as: PolicyModule22
  alias Hologram.Test.Fixtures.Policy.Module23, as: PolicyModule23
  alias Hologram.Test.Fixtures.Policy.Module24, as: PolicyModule24
  alias Hologram.Test.Fixtures.Policy.Module3, as: PolicyModule3
  alias Hologram.Test.Fixtures.Policy.Module6, as: PolicyModule6
  alias Hologram.Test.Fixtures.Policy.Module9, as: PolicyModule9
  alias Hologram.Test.Fixtures.Role

  @derived_mapping Mapper.derive!(
                     [
                       Module1,
                       Module2,
                       Module32,
                       Module33,
                       Module34,
                       Module37,
                       Module38,
                       Module39,
                       Module40,
                       Module41,
                       Module42
                     ],
                     []
                   )

  @mapping Mapper.derive!([Module1, Module2, Module3], [])

  @policy_mapping Mapper.derive!(
                    [
                      Module14,
                      PolicyModule1,
                      PolicyModule2,
                      PolicyModule3,
                      PolicyModule6,
                      RoleGrant
                    ],
                    [Role.Module1, Role.Module2]
                  )

  @quantifier_mapping Mapper.derive!([Module26, Module27, Module28, Module29], [])

  @time_mapping Mapper.derive!([Module22, Module23], [])

  defp create_module_2_entities do
    {:ok, first} =
      %{a: true, c: "banana"}
      |> Module2.new()
      |> create()

    {:ok, second} =
      %{a: false, c: "apple"}
      |> Module2.new()
      |> create()

    {:ok, third} =
      %{a: true, b: 7, c: "cherry"}
      |> Module2.new()
      |> create()

    {first, second, third}
  end

  defp create_module_3_entity do
    {:ok, target} = create(Module1.new())

    {:ok, entity} =
      %{c_id: target.id}
      |> Module3.new()
      |> create()

    entity
  end

  describe "run_policied/4" do
    # run_policied/4 composes read rules only, so the global reference (declared for :archive)
    # is executed through the compiler and the connection directly.
    defp archivable_ids(actor_user_id) do
      policy = %{
        anonymous?: false,
        rules: Policy.build(PolicyModule2)[:archive]
      }

      compiled =
        PolicyModule2
        |> Stage.normalize()
        |> QueryCompiler.compile(@policy_mapping, policy)

      values =
        Enum.map(compiled.params, fn
          :actor -> Codec.encode(actor_user_id, :uuid)
          {:value, value} -> value
        end)

      {:ok, %{rows: rows}} = Connection.query(compiled.sql, values)

      Enum.map(rows, fn [id | _rest] -> Codec.decode(id, :uuid) end)
    end

    defp create_policy_child(parent, public) do
      %{parent_id: parent.id, public: public}
      |> PolicyModule1.new()
      |> DB.create!()
    end

    defp create_policy_container(children) do
      container = DB.create!(PolicyModule3.new())

      Enum.each(children, &add_relationship(PolicyModule3, container.id, :children, &1.id))

      container
    end

    defp create_policy_entity(public) do
      %{public: public}
      |> PolicyModule1.new()
      |> DB.create!()
    end

    defp create_policy_parent do
      DB.create!(PolicyModule2.new())
    end

    defp create_policy_user(email) do
      %{email: email}
      |> Module14.new()
      |> DB.create!()
    end

    defp create_self_delegating(values) do
      values
      |> PolicyModule9.new()
      |> DB.create!()
    end

    defp disjunction_readable_ids(actor_user_id) do
      PolicyModule6
      |> Stage.normalize()
      |> run_policied(@policy_mapping, actor_user_id)
      |> Enum.map(& &1.id)
      |> Enum.sort()
    end

    defp included_children(actor_user_id) do
      term =
        PolicyModule3
        |> include(children)
        |> Stage.normalize()

      [row] = run_policied(term, @policy_mapping, actor_user_id)

      row.children
    end

    defp included_parent(actor_user_id) do
      term =
        PolicyModule1
        |> include(parent)
        |> Stage.normalize()

      [row] = run_policied(term, @policy_mapping, actor_user_id)

      row.parent
    end

    defp policied_ids(actor_user_id) do
      term = Stage.normalize(PolicyModule1)

      term
      |> run_policied(@policy_mapping, actor_user_id)
      |> Enum.map(& &1.id)
      |> Enum.sort()
    end

    test "returns only the rows the policy grants the acting user" do
      user = create_policy_user("runner_1@example.com")
      public_entity = create_policy_entity(true)
      private_entity = create_policy_entity(false)

      Auth.grant_role(user, :viewer, private_entity)

      assert policied_ids(user.id) == Enum.sort([public_entity.id, private_entity.id])
    end

    test "hides rows granted to another user" do
      user = create_policy_user("runner_2@example.com")
      other_user = create_policy_user("runner_3@example.com")
      public_entity = create_policy_entity(true)
      private_entity = create_policy_entity(false)

      Auth.grant_role(other_user, :viewer, private_entity)

      assert policied_ids(user.id) == [public_entity.id]
    end

    test "returns only unconditionally visible rows for an anonymous session" do
      user = create_policy_user("runner_4@example.com")
      public_entity = create_policy_entity(true)
      private_entity = create_policy_entity(false)

      Auth.grant_role(user, :viewer, private_entity)

      assert policied_ids(nil) == [public_entity.id]
    end

    test "returns the rows an alternative of a rule's disjunction admits" do
      user = create_policy_user("runner_20@example.com")
      other_user = create_policy_user("runner_21@example.com")

      own_entity =
        %{author_id: user.id}
        |> PolicyModule6.new()
        |> DB.create!()

      shared_entity =
        %{shared: true}
        |> PolicyModule6.new()
        |> DB.create!()

      %{author_id: other_user.id}
      |> PolicyModule6.new()
      |> DB.create!()

      assert disjunction_readable_ids(user.id) == Enum.sort([own_entity.id, shared_entity.id])
    end

    # A visitor holds no row through the alternative naming the acting user, the authorless row
    # included - only the alternative naming nobody admits anything.
    test "answers a visitor through the alternative naming nobody" do
      user = create_policy_user("runner_22@example.com")

      %{author_id: user.id}
      |> PolicyModule6.new()
      |> DB.create!()

      DB.create!(PolicyModule6.new())

      shared_entity =
        %{shared: true}
        |> PolicyModule6.new()
        |> DB.create!()

      assert disjunction_readable_ids(nil) == [shared_entity.id]
    end

    test "returns rows granted through a global role module" do
      user = create_policy_user("runner_10@example.com")
      other_user = create_policy_user("runner_11@example.com")

      entity = DB.create!(PolicyModule2.new())

      insert_global_grant(user.id, Role.Module1)

      assert archivable_ids(user.id) == [entity.id]
      assert archivable_ids(other_user.id) == []
    end

    test "applies the policy to counting queries" do
      create_policy_entity(true)
      create_policy_entity(false)

      term =
        PolicyModule1
        |> Query.count()
        |> Stage.normalize()

      assert run_policied(term, @policy_mapping, nil) == 1
    end

    test "applies the policy to single-result queries" do
      public_entity = create_policy_entity(true)
      private_entity = create_policy_entity(false)

      private_term =
        PolicyModule1
        |> filter(id: ^private_entity.id)
        |> Query.one()
        |> Stage.normalize()

      public_term =
        PolicyModule1
        |> filter(id: ^public_entity.id)
        |> Query.one()
        |> Stage.normalize()

      assert run_policied(private_term, @policy_mapping, nil) == nil
      assert %{id: id} = run_policied(public_term, @policy_mapping, nil)
      assert id == public_entity.id
    end

    test "binds authored placeholders alongside the actor slot" do
      user = create_policy_user("runner_16@example.com")

      public_match =
        %{priority: 5, public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      granted_match =
        %{priority: 5}
        |> PolicyModule1.new()
        |> DB.create!()

      %{priority: 5}
      |> PolicyModule1.new()
      |> DB.create!()

      %{priority: 9, public: true}
      |> PolicyModule1.new()
      |> DB.create!()

      Auth.grant_role(user, :viewer, granted_match)

      term = %{
        Stage.normalize(PolicyModule1)
        | filter: [{:priority, :==, {:placeholder, :priority}}]
      }

      ids =
        term
        |> run_policied(@policy_mapping, user.id, %{priority: 5})
        |> Enum.map(& &1.id)
        |> Enum.sort()

      assert ids == Enum.sort([public_match.id, granted_match.id])
    end

    test "hides an included row the policy denies the acting user" do
      user = create_policy_user("runner_12@example.com")
      parent = create_policy_parent()
      create_policy_child(parent, true)

      assert included_parent(user.id) == nil
    end

    test "embeds an included row the policy grants the acting user" do
      user = create_policy_user("runner_13@example.com")
      parent = create_policy_parent()
      create_policy_child(parent, true)

      Auth.grant_role(user, :member, parent)

      assert included_parent(user.id).id == parent.id
    end

    test "hides an included row from an anonymous session" do
      parent = create_policy_parent()
      create_policy_child(parent, true)

      assert included_parent(nil) == nil
    end

    test "filters a to-many include by the included type's policy" do
      user = create_policy_user("runner_14@example.com")
      parent = create_policy_parent()
      visible_child = create_policy_child(parent, true)
      hidden_child = create_policy_child(parent, false)
      create_policy_container([visible_child, hidden_child])

      included_ids =
        user.id
        |> included_children()
        |> Enum.map(& &1.id)

      assert included_ids == [visible_child.id]
    end

    test "applies the policy at every include level" do
      user = create_policy_user("runner_15@example.com")
      parent = create_policy_parent()
      child = create_policy_child(parent, true)
      create_policy_container([child])

      term =
        PolicyModule3
        |> include(children.parent)
        |> Stage.normalize()

      assert [%{children: [included_child]}] = run_policied(term, @policy_mapping, user.id)

      assert included_child.id == child.id
      assert included_child.parent == nil
    end

    # The related row is a row of the same type, so the statement has to tell the two apart - and
    # what it reads has to be what can? answers, row by row.
    test "reads a row through a delegation back to its own entity type" do
      editable = create_self_delegating(%{archived: false})
      archived = create_self_delegating(%{archived: true})
      editable_child = create_self_delegating(%{parent_id: editable.id})
      archived_child = create_self_delegating(%{parent_id: archived.id})
      mapping = Mapper.derive!([PolicyModule9], [])

      ids =
        PolicyModule9
        |> Stage.normalize()
        |> run_policied(mapping, nil)
        |> Enum.map(& &1.id)

      assert ids == [editable_child.id]

      readable =
        Enum.filter(
          [editable, archived, editable_child, archived_child],
          &Auth.can?(nil, :read, &1)
        )

      assert readable == [editable_child]
    end

    test "leaves the trusted run unrestricted" do
      public_entity = create_policy_entity(true)
      private_entity = create_policy_entity(false)

      ids =
        PolicyModule1
        |> Stage.normalize()
        |> run(@policy_mapping)
        |> Enum.map(& &1.id)
        |> Enum.sort()

      assert ids == Enum.sort([public_entity.id, private_entity.id])
    end
  end

  describe "run_policied/4 for quantified rules" do
    defp quantified_mapping do
      Mapper.derive!(
        [
          Module14,
          PolicyModule17,
          PolicyModule18,
          PolicyModule19,
          PolicyModule20,
          PolicyModule21,
          PolicyModule22,
          PolicyModule23,
          PolicyModule24
        ],
        []
      )
    end

    setup do
      member_user =
        %{email: "member@example.com"}
        |> Module14.new()
        |> DB.create!()

      outsider =
        %{email: "outsider@example.com"}
        |> Module14.new()
        |> DB.create!()

      closed =
        %{name: "closed"}
        |> PolicyModule17.new()
        |> DB.create!()

      open =
        %{name: "open", public: true}
        |> PolicyModule17.new()
        |> DB.create!()

      %{project_id: closed.id, user_id: member_user.id}
      |> PolicyModule18.new()
      |> DB.create!()

      %{closed: closed, member_user: member_user, open: open, outsider: outsider}
    end

    # A project reads when public, or for the user of one of its members - read raw, since a member
    # with no full seat is one nobody may read.
    defp readable_project_names(actor_user_id) do
      PolicyModule17
      |> Stage.normalize()
      |> run_policied(quantified_mapping(), actor_user_id)
      |> Enum.map(& &1.name)
      |> Enum.sort()
    end

    test "reads a project a member of it reads", %{member_user: member_user} do
      assert readable_project_names(member_user.id) == ["closed", "open"]
    end

    test "reads only the public project for an outsider", %{outsider: outsider} do
      assert readable_project_names(outsider.id) == ["open"]
    end

    test "reads only the public project for a visitor" do
      assert readable_project_names(nil) == ["open"]
    end
  end

  describe "run/3" do
    test "binds a placeholder inside a disjunction" do
      {_first, second, third} = create_module_2_entities()

      term = %{
        Stage.normalize(Module2)
        | filter: [{:or, [[{:a, :==, false}], [{:b, :==, {:placeholder, :value}}]]}]
      }

      ids =
        term
        |> run(@mapping, %{value: 7})
        |> Enum.map(& &1.id)
        |> Enum.sort()

      assert ids == Enum.sort([second.id, third.id])
    end

    test "binds membership element placeholders" do
      {_first, _second, third} = create_module_2_entities()

      term = %{Stage.normalize(Module2) | filter: [{:b, :in, [{:placeholder, :bound}, 3]}]}

      assert [%{id: id, b: 7}] = run(term, @mapping, %{bound: 7})
      assert id == third.id
    end

    # Constraint options are write-side semantics - a placeholder binding checks the type
    # only, and an out-of-constraint value is a query matching nothing, not an
    # invalid query.
    test "binds placeholder values violating declared constraint options" do
      {:ok, _entity} =
        %{count: 5}
        |> Module10.new()
        |> create()

      mapping = Mapper.derive!([Module10], [])
      term = %{Stage.normalize(Module10) | filter: [{:count, :==, {:placeholder, :count}}]}

      assert run(term, mapping, %{count: 999}) == []
    end

    test "binds placeholder values with the slot's type" do
      {first, _second, _third} = create_module_2_entities()

      term = %{Stage.normalize(Module2) | filter: [{:c, :==, {:placeholder, :search}}]}
      result = run(term, @mapping, %{search: "banana"})

      assert [%{id: id, c: "banana"}] = result
      assert id == first.id
    end

    test "binds a placeholder on a path with the type of the attribute it ends at" do
      required = DB.create!(Module1.new())

      target =
        %{a: true, c: "banana"}
        |> Module2.new()
        |> DB.create!()

      source =
        %{b_id: target.id, c_id: required.id}
        |> Module3.new()
        |> DB.create!()

      term = %{Stage.normalize(Module3) | filter: [{[:b, :c], :==, {:placeholder, :search}}]}

      assert [%{id: id}] = run(term, @mapping, %{search: "banana"})
      assert id == source.id
    end

    test "counts matching entities" do
      create_module_2_entities()

      term =
        Module2
        |> filter(a: true)
        |> count()
        |> Stage.normalize()

      assert run(term, @mapping) == 2
    end

    test "decodes a to-many include with nested clauses" do
      {first, _second, third} = create_module_2_entities()
      source = create_module_3_entity()

      :ok = add_relationship(Module3, source.id, :a, first.id)
      :ok = add_relationship(Module3, source.id, :a, third.id)

      term =
        Module3
        |> narrowed_include(:a, fn related_query ->
          related_query
          |> filter(a: true)
          |> sort(c)
        end)
        |> Stage.normalize()

      assert [%Module3{a: related_entities}] = run(term, @mapping)
      assert [%Module2{c: "banana"}, %Module2{b: 7, c: "cherry"}] = related_entities
    end

    # An embedded row travels as JSON, which writes a fraction without its trailing zeros, while
    # the same row read from its own columns carries all six digits. Left alone, one instant
    # would decode into two structs that compare unequal, and an application reading a row two
    # ways would be told they are different rows.
    test "decodes an embedded datetime the way the column path decodes it" do
      {target, _second, _third} = create_module_2_entities()
      source = create_module_3_entity()

      :ok = add_relationship(Module3, source.id, :a, target.id)

      stamp = ~U[2026-08-16 12:00:00.457870Z]

      {:ok, _result} =
        Connection.query(
          ~s(UPDATE "hologram_data".#{Mapper.quote_identifier(Mapper.table_name(Module2))} SET "created_at" = $1 WHERE "id" = $2),
          [stamp, Codec.encode(target.id, :uuid)]
        )

      embedding_term =
        Module3
        |> include(a)
        |> Stage.normalize()

      direct_term =
        Module2
        |> filter(id: ^target.id)
        |> one()
        |> Stage.normalize()

      assert [%Module3{a: [embedded]}] = run(embedding_term, @mapping)

      assert embedded.created_at == run(direct_term, @mapping).created_at
      assert embedded.created_at == stamp
    end

    # The same trap as the datetime above, one type over: a time column is time(6) and always
    # reads back with six fractional digits, while JSON drops a fraction's trailing zeros - so an
    # embedded 11am and a column-read 11am would be two structs of one time of day.
    test "decodes an embedded time the way the column path decodes it" do
      {:ok, target} =
        %{opens_at: ~T[11:00:00]}
        |> Module22.new()
        |> create()

      {:ok, source} =
        %{a_id: target.id}
        |> Module23.new()
        |> create()

      embedding_term =
        Module23
        |> filter(id: ^source.id)
        |> include(a)
        |> one()
        |> Stage.normalize()

      direct_term =
        Module22
        |> filter(id: ^target.id)
        |> one()
        |> Stage.normalize()

      assert %Module23{a: %Module22{} = embedded} = run(embedding_term, @time_mapping)

      assert embedded.opens_at == run(direct_term, @time_mapping).opens_at
      assert embedded.opens_at == ~T[11:00:00.000000]
    end

    test "decodes an embedded time whose fraction JSON stripped to fewer digits" do
      {:ok, target} =
        %{opens_at: ~T[11:00:00.100000]}
        |> Module22.new()
        |> create()

      {:ok, source} =
        %{a_id: target.id}
        |> Module23.new()
        |> create()

      term =
        Module23
        |> filter(id: ^source.id)
        |> include(a)
        |> one()
        |> Stage.normalize()

      assert run(term, @time_mapping).a.opens_at == ~T[11:00:00.100000]
    end

    test "decodes a to-one include as a nested entity struct" do
      source = create_module_3_entity()

      term =
        Module3
        |> include(c)
        |> Stage.normalize()

      assert [%Module3{id: id, c: %Module1{} = embedded_entity}] = run(term, @mapping)
      assert id == source.id
      assert embedded_entity.id == source.c_id
      assert %DateTime{} = embedded_entity.created_at
    end

    test "fills the metadata of every row of a set read" do
      {first, second, _third} = create_module_2_entities()

      set_revisions(Module2, first.id, %{"a" => 3, "c" => 2})
      set_revisions(Module2, second.id, %{"c" => 5})

      term = Stage.normalize(Module2)

      revisions =
        term
        |> run(@mapping)
        |> Map.new(&{&1.id, &1.__meta__.revisions})

      assert revisions[first.id] == %{a: 3, c: 2}
      assert revisions[second.id] == %{c: 5}
    end

    test "fills the metadata of an included row" do
      {:ok, required_target} = create(Module1.new())

      {:ok, included_target} =
        %{a: true, c: "abc"}
        |> Module2.new()
        |> create()

      {:ok, _source} =
        %{b_id: included_target.id, c_id: required_target.id}
        |> Module3.new()
        |> create()

      set_revisions(Module2, included_target.id, %{"a" => 3, "c" => 2})

      term =
        Module3
        |> include(b)
        |> Stage.normalize()

      assert [%Module3{b: %Module2{} = embedded_entity}] = run(term, @mapping)
      assert embedded_entity.__meta__.revisions == %{a: 3, c: 2}
    end

    test "embeds an included row the read policy hides from an acting user" do
      parent = DB.create!(PolicyModule2.new())

      %{parent_id: parent.id, public: true}
      |> PolicyModule1.new()
      |> DB.create!()

      term =
        PolicyModule1
        |> include(parent)
        |> Stage.normalize()

      assert [%{parent: included_parent}] = run(term, @policy_mapping)
      assert included_parent.id == parent.id
    end

    test "decodes an absent optional to-one include as nil" do
      create_module_3_entity()

      term =
        Module3
        |> include(b)
        |> Stage.normalize()

      assert [%{b: nil}] = run(term, @mapping)
    end

    test "defaults not-included relationships to the sentinel" do
      create_module_3_entity()

      term = Stage.normalize(Module3)

      assert [%Module3{} = entity] = run(term, @mapping)
      assert entity.a == %NotIncluded{relationship: :a}
      assert entity.b == %NotIncluded{relationship: :b}
      assert entity.c == %NotIncluded{relationship: :c}
    end

    test "filters and orders a to-many include whose target names columns like the join table" do
      {:ok, source} = create(Module9.new())

      {:ok, first_target} =
        %{source_id: 5}
        |> Module8.new()
        |> create()

      {:ok, second_target} =
        %{source_id: 1}
        |> Module8.new()
        |> create()

      :ok = add_relationship(Module9, source.id, :a, first_target.id)
      :ok = add_relationship(Module9, source.id, :a, second_target.id)

      mapping = Mapper.derive!([Module8, Module9], [])

      term =
        Module9
        |> narrowed_include(:a, fn related_query ->
          related_query
          |> filter(source_id >= 2)
          |> sort(source_id)
        end)
        |> Stage.normalize()

      assert [%Module9{a: [%Module8{source_id: 5}]}] = run(term, mapping)
    end

    test "matches nothing for an empty membership list binding" do
      create_module_2_entities()

      term = %{Stage.normalize(Module2) | filter: [{:b, :in, {:placeholder, :ids}}]}

      assert run(term, @mapping, %{ids: []}) == []
    end

    test "filters by a to-one reference field" do
      matching = create_module_3_entity()
      create_module_3_entity()

      term =
        Module3
        |> filter(c_id: ^matching.c_id)
        |> Stage.normalize()

      assert [%Module3{id: id, c_id: c_id}] = run(term, @mapping)
      assert id == matching.id
      assert c_id == matching.c_id
    end

    test "filters by a to-one reference field bound as a placeholder" do
      matching = create_module_3_entity()
      create_module_3_entity()

      term = %{Stage.normalize(Module3) | filter: [{:c_id, :==, {:placeholder, :target}}]}

      assert [%Module3{id: id}] = run(term, @mapping, %{target: matching.c_id})
      assert id == matching.id
    end

    test "returns entity structs filtered and ordered" do
      {first, _second, third} = create_module_2_entities()

      term =
        Module2
        |> filter(a: true)
        |> sort(c)
        |> Stage.normalize()

      assert [
               %Module2{id: first_id, a: true, b: nil, c: "banana"},
               %Module2{id: third_id, a: true, b: 7, c: "cherry"}
             ] = run(term, @mapping)

      assert first_id == first.id
      assert third_id == third.id
    end

    test "returns nil when no entity matches a single-result query" do
      term =
        Module2
        |> filter(c: "missing")
        |> one()
        |> Stage.normalize()

      assert run(term, @mapping) == nil
    end

    test "returns the first entity under the total order for single-result queries" do
      {_first, second, _third} = create_module_2_entities()

      term =
        Module2
        |> sort(c)
        |> one()
        |> Stage.normalize()

      assert %{id: id, c: "apple"} = run(term, @mapping)
      assert id == second.id
    end

    test "raises on a malformed id placeholder value" do
      term = %{Stage.normalize(Module2) | filter: [{:id, :==, {:placeholder, :entity_id}}]}

      expected_msg =
        ~s(invalid value "not-a-uuid" for placeholder :entity_id - expected a :uuid value)

      assert_error ArgumentError, expected_msg, fn ->
        run(term, @mapping, %{entity_id: "not-a-uuid"})
      end
    end

    test "raises on a membership binding that is not a list" do
      term = %{Stage.normalize(Module2) | filter: [{:b, :in, {:placeholder, :ids}}]}

      expected_msg =
        "non-list value 5 for placeholder :ids - the placeholder binds a membership list"

      assert_error ArgumentError, expected_msg, fn ->
        run(term, @mapping, %{ids: 5})
      end
    end

    test "validates a placeholder binding beside an included derived value" do
      term =
        Module37
        |> filter(name == ^%Placeholder{name: :name})
        |> include(pinned_count)
        |> Stage.normalize()

      expected_msg = "invalid value 5 for placeholder :name - expected a :string value"

      assert_error ArgumentError, expected_msg, fn ->
        run(term, @mapping, %{name: 5})
      end
    end

    test "raises on a placeholder binding a derived field does not take" do
      term =
        Module37
        |> filter(pinned_count > ^%Placeholder{name: :threshold})
        |> Stage.normalize()

      expected_msg =
        ~s(invalid value "many" for placeholder :threshold - expected a :integer value)

      assert_error ArgumentError, expected_msg, fn ->
        run(term, @mapping, %{threshold: "many"})
      end
    end

    test "raises on a membership element of the wrong type" do
      term = %{Stage.normalize(Module2) | filter: [{:b, :in, {:placeholder, :ids}}]}

      expected_msg =
        ~s(invalid element "x" in the list for placeholder :ids - expected a :integer value)

      assert_error ArgumentError, expected_msg, fn ->
        run(term, @mapping, %{ids: [1, "x"]})
      end
    end

    test "raises on a missing placeholder value" do
      term = %{Stage.normalize(Module2) | filter: [{:c, :==, {:placeholder, :search}}]}

      assert_error ArgumentError, "missing value for placeholder :search", fn ->
        run(term, @mapping)
      end
    end

    test "raises on a nil membership element" do
      term = %{Stage.normalize(Module2) | filter: [{:b, :in, {:placeholder, :ids}}]}

      expected_msg =
        "nil element in the list for placeholder :ids - use an explicit nil predicate instead"

      assert_error ArgumentError, expected_msg, fn ->
        run(term, @mapping, %{ids: [1, nil]})
      end
    end

    test "raises on a nil placeholder value" do
      term = %{Stage.normalize(Module2) | filter: [{:c, :==, {:placeholder, :search}}]}

      expected_msg = "nil value for placeholder :search - use an explicit nil predicate instead"

      assert_error ArgumentError, expected_msg, fn ->
        run(term, @mapping, %{search: nil})
      end
    end

    test "raises on a placeholder binding with conflicting types" do
      term = %{
        Stage.normalize(Module2)
        | filter: [{:b, :==, {:placeholder, :x}}, {:b, :in, {:placeholder, :x}}]
      }

      expected_msg =
        "placeholder :x binds as :integer and {:list, :integer} - rename one of the conflicting variables"

      assert_error ArgumentError, expected_msg, fn ->
        run(term, @mapping, %{x: 5})
      end
    end

    # A placeholder inside an alternative is validated like any other, before the statement runs.
    test "raises on a wrongly typed placeholder inside a disjunction" do
      term = %{
        Stage.normalize(Module2)
        | filter: [{:or, [[{:a, :==, true}], [{:b, :==, {:placeholder, :value}}]]}]
      }

      expected_msg = ~s(invalid value "x" for placeholder :value - expected a :integer value)

      assert_error ArgumentError, expected_msg, fn ->
        run(term, @mapping, %{value: "x"})
      end
    end

    test "raises on a placeholder value of the wrong type" do
      term = %{Stage.normalize(Module2) | filter: [{:c, :==, {:placeholder, :search}}]}

      expected_msg = "invalid value 123 for placeholder :search - expected a :string value"

      assert_error ArgumentError, expected_msg, fn ->
        run(term, @mapping, %{search: 123})
      end
    end

    test "raises on a placeholder value on a path of the wrong type for the attribute it ends at" do
      term = %{Stage.normalize(Module3) | filter: [{[:b, :c], :==, {:placeholder, :search}}]}

      expected_msg = "invalid value 123 for placeholder :search - expected a :string value"

      assert_error ArgumentError, expected_msg, fn ->
        run(term, @mapping, %{search: 123})
      end
    end

    test "raises on an enum placeholder value inside a quantifier's condition outside the related row's declared set" do
      term = %{
        Stage.normalize(Module31)
        | filter: [{:any, {[:items], [{:priority, :==, {:placeholder, :priority}}]}}]
      }

      expected_msg =
        "invalid value :urgent for placeholder :priority - expected one of [:low, :medium, :high]"

      assert_error ArgumentError, expected_msg, fn ->
        run(term, @mapping, %{priority: :urgent})
      end
    end

    test "raises on an enum placeholder value outside the declared set" do
      term = %{Stage.normalize(Module4) | filter: [{:c, :==, {:placeholder, :choice}}]}

      expected_msg = "invalid value :z for placeholder :choice - expected one of [:x, :y]"

      assert_error ArgumentError, expected_msg, fn ->
        run(term, @mapping, %{choice: :z})
      end
    end

    test "raises on an unknown binding name" do
      term = %{Stage.normalize(Module2) | filter: [{:c, :==, {:placeholder, :search}}]}

      expected_msg =
        "unknown placeholder :serach in bindings - the query defines placeholders [:search]"

      assert_error ArgumentError, expected_msg, fn ->
        run(term, @mapping, %{search: "x", serach: "y"})
      end
    end
  end

  describe "run/3 - derived counts and sets" do
    setup do
      put_derived_definitions([Module32, Module33, Module34, Module37, Module38, Module40])
    end

    defp create_module_32_entity(name, positions) do
      {:ok, channel} = create(Module32.new(name: name))

      for position <- positions, do: create_module_33_entity(channel, position)

      channel
    end

    defp create_module_33_entity(channel, position) do
      {:ok, message} =
        %{body: "message #{position}", channel_id: channel && channel.id, position: position}
        |> Module33.new()
        |> create()

      message
    end

    defp create_module_37_entity(name, message_count) do
      {:ok, channel} = create(Module37.new(name: name))

      for _index <- 1..message_count//1 do
        {:ok, _message} =
          %{channel_id: channel.id, pinned: false}
          |> Module38.new()
          |> create()
      end

      channel
    end

    defp create_module_40_entity(name, note_publicity) do
      {:ok, team} = create(Module40.new(name: name))

      for public <- note_publicity do
        {:ok, _note} =
          %{public: public, team_id: team.id}
          |> Module41.new()
          |> create()
      end

      team
    end

    test "filters and sorts by a count" do
      create_module_32_entity("busy", [1, 2, 3])
      create_module_32_entity("quiet", [1])
      create_module_32_entity("empty", [])

      query =
        Module32
        |> filter(message_count > 0)
        |> sort(message_count: :desc)

      assert derived_query_results(query, :name) == ["busy", "quiet"]
    end

    test "counts the rows a clause reading the owner row matches" do
      create_module_32_entity("general", [1, 2, 3])

      query = filter(Module33, later_count == 1)

      assert derived_query_results(query, :position) == [2]
    end

    test "counts no rows through a missing to-one" do
      create_module_32_entity("general", [1, 2, 3])
      create_module_33_entity(nil, 5)

      query =
        Module33
        |> filter(later_count == 0)
        |> sort(position)

      assert derived_query_results(query, :position) == [3, 5]
    end

    test "counts a row several paths reach once" do
      general = create_module_32_entity("general", [1, 2])
      team = create_module_40_entity("team", [])

      for nickname <- ["ann", "gina"] do
        {:ok, mentor} =
          %{channel_id: general.id, nickname: nickname, score: 1}
          |> Module34.new()
          |> create()

        :ok = add_relationship(Module40, team.id, :mentors, mentor.id)
      end

      query = filter(Module40, mentor_message_count == 2)

      assert derived_query_results(query, :name) == ["team"]
    end

    test "caps a count by its bounds" do
      create_module_40_entity("full", [true, true, true])
      create_module_40_entity("sparse", [true])

      query = filter(Module40, capped_note_count == 2)

      assert derived_query_results(query, :name) == ["full"]
    end

    test "compares a count a float field reads as a float" do
      create_module_40_entity("full", [true, true])
      create_module_40_entity("sparse", [true])

      query = filter(Module40, note_weight > 1.5)

      assert derived_query_results(query, :name) == ["full"]
    end

    test "matches a quantifier's rows to a derived set's bounded rows" do
      create_module_32_entity("short", [1, 2])
      create_module_32_entity("long", [1, 2, 3])

      query = filter(Module32, any(message <- recent_messages, message.position == 1))

      assert derived_query_results(query, :name) == ["short"]
    end

    test "matches a quantifier's rows to a derived set reached through a to-one" do
      create_module_32_entity("short", [1, 2])
      long = create_module_32_entity("long", [1, 2, 3])

      query = filter(Module33, any(message <- channel.recent_messages, message.position == 3))

      assert derived_query_results(query, :channel_id) == [long.id, long.id, long.id]
    end

    test "counts the rows of a derived set the branch of an if chooses" do
      create_module_37_entity("general", 3)
      create_module_37_entity("random", 2)

      first_query = filter(Module37, picked_count == 1)
      all_query = filter(Module37, picked_count == 2)

      assert derived_query_results(first_query, :name) == ["general"]
      assert derived_query_results(all_query, :name) == ["random"]
    end
  end

  describe "run/3 - derived fields" do
    setup do
      put_derived_definitions([Module34, Module39])

      {:ok, general} = create(Module32.new(name: "general"))

      members =
        Map.new([{"ann", 1, general}, {"bob", 5, nil}, {"general", 0, general}], fn
          {nickname, score, channel} ->
            {:ok, member} =
              %{channel_id: channel && channel.id, nickname: nickname, score: score}
              |> Module34.new()
              |> create()

            {nickname, member}
        end)

      [members: members]
    end

    defp create_module_39_entity(score, member \\ nil) do
      {:ok, entity} =
        %{kind: :guest, member_id: member && member.id, score: score}
        |> Module39.new()
        |> create()

      entity
    end

    defp derived_query_results(query, field) do
      query
      |> Stage.normalize()
      |> run(@derived_mapping)
      |> Enum.map(&Map.fetch!(&1, field))
    end

    test "filters on a derived value missing where the related row it reads is" do
      unequal_query =
        Module34
        |> filter(display_name != "ann (general)")
        |> sort(nickname)

      missing_query = filter(Module34, display_name == nil)

      assert derived_query_results(unequal_query, :nickname) == ["bob", "general"]
      assert derived_query_results(missing_query, :nickname) == ["bob"]
    end

    test "filters on a derived boolean false where its condition is not true" do
      active_query = filter(Module34, active == true)

      unnamed_query =
        Module34
        |> filter(named_after_channel == false)
        |> sort(nickname)

      assert derived_query_results(active_query, :nickname) == ["ann"]
      assert derived_query_results(unnamed_query, :nickname) == ["ann", "bob"]
    end

    test "filters on a path ending at a derived value", %{members: members} do
      create_module_39_entity(1, members["ann"])
      create_module_39_entity(2, members["bob"])

      query = filter(Module39, member.display_name == "ann (general)")

      assert derived_query_results(query, :score) == [1]
    end

    test "compares a derived enum by its declared order" do
      for score <- [1, 7, 12], do: create_module_39_entity(score)

      query =
        Module39
        |> filter(tier < :bronze)
        |> sort(score)

      assert derived_query_results(query, :score) == [7, 12]
    end

    test "compares a derived enum with an enum attribute of the row" do
      {:ok, _staff} =
        %{kind: :staff, score: 2}
        |> Module39.new()
        |> create()

      create_module_39_entity(1)

      equal_query =
        Module39
        |> filter(kind_label == kind)
        |> sort(score)

      lower_query = filter(Module39, kind < kind_label)

      assert derived_query_results(equal_query, :score) == [1, 2]
      assert derived_query_results(lower_query, :score) == []
    end

    test "computes derived fields inside a quantifier's condition", %{members: members} do
      low = create_module_39_entity(0)
      high = create_module_39_entity(6)

      :ok = add_relationship(Module39, low.id, :mentors, members["bob"].id)
      :ok = add_relationship(Module39, high.id, :mentors, members["ann"].id)

      above_query = filter(Module39, any(mentor <- mentors, mentor.score > ratio))
      related_query = filter(Module39, any(mentor <- mentors, mentor.active == true))

      assert derived_query_results(above_query, :score) == [0]
      assert derived_query_results(related_query, :score) == [6]
    end

    test "sorts by a derived enum in its declared order" do
      for score <- [7, 1, 12], do: create_module_39_entity(score)

      query = sort(Module39, tier: :asc)

      assert derived_query_results(query, :score) == [12, 7, 1]
    end

    test "sorts a to-many include by a derived field", %{members: members} do
      source = create_module_39_entity(1)

      :ok = add_relationship(Module39, source.id, :mentors, members["ann"].id)
      :ok = add_relationship(Module39, source.id, :mentors, members["bob"].id)

      query =
        narrowed_include(Module39, :mentors, fn related_query ->
          sort(related_query, active: :asc)
        end)

      assert [mentors] = derived_query_results(query, :mentors)
      assert Enum.map(mentors, & &1.nickname) == ["bob", "ann"]
    end
  end

  describe "run/3 - derived includes" do
    setup do
      put_derived_definitions([
        Module32,
        Module33,
        Module34,
        Module37,
        Module38,
        Module39,
        Module40
      ])
    end

    defp create_module_38_entity(channel, author) do
      {:ok, message} =
        %{author_id: author && author.id, channel_id: channel.id, pinned: false}
        |> Module38.new()
        |> create()

      message
    end

    test "includes a derived value read by its declared type" do
      create_module_32_entity("general", [1, 2, 3])
      create_module_39_entity(7)

      [channel] =
        Module32
        |> include(message_count)
        |> derived_query_results(:message_count)

      [entity] =
        Module39
        |> include([ratio, tier])
        |> Stage.normalize()
        |> run(@derived_mapping)

      assert channel == 3
      assert entity.ratio === 7.0
      assert entity.tier == :silver
    end

    test "includes a count a float field reads as a float" do
      {:ok, team} = create(Module40.new(name: "team"))

      {:ok, _note} =
        %{public: true, team_id: team.id}
        |> Module41.new()
        |> create()

      results =
        Module40
        |> include(note_weight)
        |> derived_query_results(:note_weight)

      assert results === [1.0]
    end

    test "includes a derived set's rows in its order, its bounds applied" do
      create_module_32_entity("general", [1, 2, 3])

      [recent_messages] =
        Module32
        |> include(recent_messages)
        |> derived_query_results(:recent_messages)

      assert Enum.map(recent_messages, & &1.position) == [3, 2]
    end

    test "includes a derived row, or nil where there is none" do
      create_module_32_entity("busy", [2, 1])
      create_module_32_entity("empty", [])

      first_messages =
        Module32
        |> include(first_message)
        |> sort(name)
        |> derived_query_results(:first_message)

      assert [%Module33{position: 1}, nil] = first_messages
    end

    test "includes a related row under a derived set's rows" do
      {:ok, channel} = create(Module37.new(name: "general"))
      {:ok, author} = create(Module1.new())
      create_module_38_entity(channel, author)

      [[message]] =
        Module37
        |> include(recent_messages.author)
        |> derived_query_results(:recent_messages)

      assert message.author.id == author.id
    end

    test "includes what a derived set's definition includes" do
      {:ok, channel} = create(Module37.new(name: "general"))
      {:ok, author} = create(Module1.new())
      create_module_38_entity(channel, author)

      [[message]] =
        Module37
        |> include(authored_messages)
        |> derived_query_results(:authored_messages)

      assert message.author.id == author.id
      assert message.channel == %NotIncluded{relationship: :channel}
    end

    test "includes the rows of the branch an if chooses, and none for nil" do
      create_module_37_entity("general", 3)
      create_module_37_entity("random", 2)

      results =
        Module37
        |> include([nothing, picked])
        |> sort(name)
        |> Stage.normalize()
        |> run(@derived_mapping)

      assert Enum.map(results, &length(&1.picked)) == [1, 2]
      assert Enum.map(results, & &1.nothing) == [[], []]
    end

    test "includes a derived value under a related row, read by its declared type" do
      create_module_32_entity("general", [1, 2, 3])
      team = create_module_40_entity("team", [])
      player = create_module_39_entity(7)

      :ok = add_relationship(Module40, team.id, :players, player.id)

      [messages] =
        Module32
        |> include([messages.later_count, messages.tier])
        |> derived_query_results(:messages)

      [[included_player]] =
        Module40
        |> include(players.ratio)
        |> derived_query_results(:players)

      assert Enum.map(messages, &{&1.later_count, &1.tier}) == [{2, :low}, {1, :low}, {0, :low}]
      assert included_player.ratio === 7.0
    end

    test "includes the row a skip leaves first, and nil for a field holding none" do
      team = create_module_40_entity("team", [true, true, true])

      [_first_id, second_id, _third_id] =
        Module41
        |> filter(team_id == ^team.id)
        |> derived_query_results(:id)

      [included_team] =
        Module40
        |> include([no_note, second_note])
        |> Stage.normalize()
        |> run(@derived_mapping)

      assert included_team.second_note.id == second_id
      assert included_team.no_note == nil
    end
  end

  describe "run/3 - quantifiers" do
    setup do
      {:ok, general} = create(Module26.new(name: "general"))
      {:ok, _quiet} = create(Module26.new(name: "quiet"))
      {:ok, late} = create(Module26.new(name: "late"))

      for {body, position, channel} <- [
            {"hi", 1, general},
            {"hidden", 3, general},
            {"bye", 4, late},
            {"ciao", 5, late}
          ] do
        {:ok, _message} =
          %{body: body, channel_id: channel.id, position: position}
          |> Module28.new()
          |> create()
      end

      :ok
    end

    test "answers any, none and all over a channel's messages" do
      names = fn query ->
        query
        |> Stage.normalize()
        |> run(@quantifier_mapping)
        |> Enum.map(& &1.name)
        |> Enum.sort()
      end

      any_query = filter(Module26, any(message <- messages, message.position > 3))
      none_query = filter(Module26, none(message <- messages, message.body == "hi"))
      empty_query = filter(Module26, none(messages))
      all_query = filter(Module26, all(message <- messages, message.position > 2))

      assert names.(any_query) == ["late"]
      assert names.(none_query) == ["late", "quiet"]
      assert names.(empty_query) == ["quiet"]
      assert names.(all_query) == ["late", "quiet"]
    end

    test "counts a related row with a missing value against all" do
      source = create_module_3_entity()

      {:ok, unset} =
        %{c: "unset"}
        |> Module2.new()
        |> create()

      :ok = add_relationship(Module3, source.id, :a, unset.id)

      term =
        Module3
        |> filter(all(item <- a, item.b > 1))
        |> Stage.normalize()

      assert run(term, @mapping) == []
    end
  end

  describe "run_policied/4 - derived fields" do
    # A rule reads the rows its paths reach as stored, whatever the session may read of them - so
    # a derived field in a condition does too: the note the hidden row names is one an anonymous
    # session may not read, and the rule still reads it.
    test "reads the path of a derived field in a rule as stored" do
      put_derived_definitions([Module42])

      for {caption, public} <- [{"hidden", false}, {"shown", true}, {"none", nil}] do
        note_id =
          if public != nil do
            {:ok, note} = create(Module41.new(public: public))

            note.id
          end

        {:ok, _row} =
          %{note_id: note_id, score: 1, caption: caption}
          |> Module42.new()
          |> create()
      end

      captions =
        Module42
        |> Stage.normalize()
        |> run_policied(@derived_mapping, nil)
        |> Enum.map(& &1.caption)

      assert captions == ["hidden"]
    end

    test "leaves a related row the session may not read out of a count" do
      put_derived_definitions([Module40])

      {:ok, team} = create(Module40.new(name: "team"))

      for public <- [true, false] do
        {:ok, _note} =
          %{public: public, team_id: team.id}
          |> Module41.new()
          |> create()
      end

      term =
        Module40
        |> filter(note_count == 1)
        |> Stage.normalize()

      policied_rows = run_policied(term, @derived_mapping, nil)
      raw_rows = run(term, @derived_mapping)

      assert Enum.map(policied_rows, & &1.name) == ["team"]
      assert raw_rows == []
    end

    test "leaves a row the session may not read out of an included derived set" do
      put_derived_definitions([Module40])

      {:ok, team} = create(Module40.new(name: "tagged"))

      for public <- [true, false] do
        {:ok, _note} =
          %{public: public, team_id: team.id}
          |> Module41.new()
          |> create()
      end

      term =
        Module40
        |> include(picked_notes)
        |> Stage.normalize()

      [policied_team] = run_policied(term, @derived_mapping, nil)

      assert [%Module41{public: true, tags: []}] = policied_team.picked_notes
    end

    test "leaves a row the session may not read out of the rows a count's source passes through" do
      put_derived_definitions([Module40])

      {:ok, team} = create(Module40.new(name: "team"))

      for {public, tag_name} <- [{true, "shown"}, {false, "hidden"}] do
        {:ok, note} =
          %{public: public, team_id: team.id}
          |> Module41.new()
          |> create()

        {:ok, tag} = create(Module2.new(c: tag_name))

        :ok = add_relationship(Module41, note.id, :tags, tag.id)
      end

      term =
        Module40
        |> filter(note_tag_count == 1)
        |> Stage.normalize()

      policied_rows = run_policied(term, @derived_mapping, nil)
      raw_rows = run(term, @derived_mapping)

      assert Enum.map(policied_rows, & &1.name) == ["team"]
      assert raw_rows == []
    end
  end

  describe "run_policied/4 - quantifiers" do
    test "leaves a related row the session may not read out of the set" do
      {:ok, general} = create(Module26.new(name: "general"))
      {:ok, _quiet} = create(Module26.new(name: "quiet"))

      {:ok, _hidden} =
        %{body: "hidden", channel_id: general.id, position: 1}
        |> Module28.new()
        |> create()

      term =
        Module26
        |> filter(none(message <- messages, message.body == "hidden"))
        |> Stage.normalize()

      # Two channels created in one millisecond come back in no order a test can name.
      policied_names =
        term
        |> run_policied(@quantifier_mapping, nil)
        |> Enum.map(& &1.name)
        |> Enum.sort()

      raw_rows = run(term, @quantifier_mapping)

      assert policied_names == ["general", "quiet"]
      assert Enum.map(raw_rows, & &1.name) == ["quiet"]
    end
  end
end
