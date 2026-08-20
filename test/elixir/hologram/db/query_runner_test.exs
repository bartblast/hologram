defmodule Hologram.DB.QueryRunnerTest do
  use Hologram.Test.DatabaseCase, async: true
  use Hologram.Query

  import Hologram.DB.EntityOperations, only: [add_relationship: 4, create: 1]
  import Hologram.DB.QueryRunner

  alias Hologram.Auth
  alias Hologram.Auth.RoleGrant
  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.DB.QueryCompiler
  alias Hologram.Entity
  alias Hologram.Entity.NotIncluded
  alias Hologram.Policy
  alias Hologram.Query
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module10
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module4
  alias Hologram.Test.Fixtures.Entity.Module8
  alias Hologram.Test.Fixtures.Entity.Module9
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyModule1
  alias Hologram.Test.Fixtures.Policy.Module2, as: PolicyModule2
  alias Hologram.Test.Fixtures.Policy.Module3, as: PolicyModule3
  alias Hologram.Test.Fixtures.Role

  @mapping Mapper.derive!([Module1, Module2, Module3])

  @policy_mapping Mapper.derive!([
                    Module14,
                    PolicyModule1,
                    PolicyModule2,
                    PolicyModule3,
                    RoleGrant
                  ])

  defp create_module_2_entities do
    first =
      Module2
      |> Entity.new(a: true, c: "banana")
      |> create()

    second =
      Module2
      |> Entity.new(a: false, c: "apple")
      |> create()

    third =
      Module2
      |> Entity.new(a: true, b: 7, c: "cherry")
      |> create()

    {first, second, third}
  end

  defp create_module_3_entity do
    target =
      Module1
      |> Entity.new()
      |> create()

    Module3
    |> Entity.new(c_id: target.id)
    |> create()
  end

  describe "run_policied/4" do
    # run_policied/4 composes read rules only, so the global reference (declared for :archive)
    # is executed through the compiler and the connection directly.
    defp archivable_ids(actor_user_id) do
      policy = %{
        anonymous?: false,
        operation: :archive,
        rules: Policy.build(PolicyModule2)[:archive]
      }

      compiled =
        PolicyModule2
        |> Query.normalize()
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
      PolicyModule1
      |> Entity.new(parent_id: parent.id, public: public)
      |> DB.create()
    end

    defp create_policy_entity(public) do
      PolicyModule1
      |> Entity.new(public: public)
      |> DB.create()
    end

    defp create_policy_container(children) do
      container =
        PolicyModule3
        |> Entity.new()
        |> DB.create()

      Enum.each(children, &add_relationship(PolicyModule3, container.id, :children, &1.id))

      container
    end

    defp create_policy_parent do
      PolicyModule2
      |> Entity.new()
      |> DB.create()
    end

    defp create_policy_user(email) do
      Module14
      |> Entity.new(email: email)
      |> DB.create()
    end

    defp included_children(actor_user_id) do
      term =
        PolicyModule3
        |> include(:children)
        |> Query.normalize()

      [row] = run_policied(term, @policy_mapping, actor_user_id)

      row.children
    end

    defp included_parent(actor_user_id) do
      term =
        PolicyModule1
        |> include(:parent)
        |> Query.normalize()

      [row] = run_policied(term, @policy_mapping, actor_user_id)

      row.parent
    end

    defp policied_ids(actor_user_id) do
      term = Query.normalize(PolicyModule1)

      term
      |> run_policied(@policy_mapping, actor_user_id)
      |> Enum.map(& &1.id)
      |> Enum.sort()
    end

    test "returns only the rows the policy grants the acting user" do
      user = create_policy_user("runner_1@example.com")
      public_entity = create_policy_entity(true)
      private_entity = create_policy_entity(false)

      Auth.grant_role(user, private_entity, :viewer)

      assert policied_ids(user.id) == Enum.sort([public_entity.id, private_entity.id])
    end

    test "hides rows granted to another user" do
      user = create_policy_user("runner_2@example.com")
      other_user = create_policy_user("runner_3@example.com")
      public_entity = create_policy_entity(true)
      private_entity = create_policy_entity(false)

      Auth.grant_role(other_user, private_entity, :viewer)

      assert policied_ids(user.id) == [public_entity.id]
    end

    test "returns only unconditionally visible rows for an anonymous session" do
      user = create_policy_user("runner_4@example.com")
      public_entity = create_policy_entity(true)
      private_entity = create_policy_entity(false)

      Auth.grant_role(user, private_entity, :viewer)

      assert policied_ids(nil) == [public_entity.id]
    end

    test "returns rows granted through a global role module" do
      user = create_policy_user("runner_10@example.com")
      other_user = create_policy_user("runner_11@example.com")

      entity =
        PolicyModule2
        |> Entity.new()
        |> DB.create()

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
        |> Query.normalize()

      assert run_policied(term, @policy_mapping, nil) == 1
    end

    test "applies the policy to single-result queries" do
      public_entity = create_policy_entity(true)
      private_entity = create_policy_entity(false)

      private_term =
        PolicyModule1
        |> filter(id: private_entity.id)
        |> Query.one()
        |> Query.normalize()

      public_term =
        PolicyModule1
        |> filter(id: public_entity.id)
        |> Query.one()
        |> Query.normalize()

      assert run_policied(private_term, @policy_mapping, nil) == nil
      assert %{id: id} = run_policied(public_term, @policy_mapping, nil)
      assert id == public_entity.id
    end

    test "binds authored placeholders alongside the actor slot" do
      user = create_policy_user("runner_16@example.com")

      public_match =
        PolicyModule1
        |> Entity.new(priority: 5, public: true)
        |> DB.create()

      granted_match =
        PolicyModule1
        |> Entity.new(priority: 5)
        |> DB.create()

      PolicyModule1
      |> Entity.new(priority: 5)
      |> DB.create()

      PolicyModule1
      |> Entity.new(priority: 9, public: true)
      |> DB.create()

      Auth.grant_role(user, granted_match, :viewer)

      term = %{
        Query.normalize(PolicyModule1)
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

      Auth.grant_role(user, parent, :member)

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
        |> include(:children, &include(&1, :parent))
        |> Query.normalize()

      assert [%{children: [included_child]}] = run_policied(term, @policy_mapping, user.id)

      assert included_child.id == child.id
      assert included_child.parent == nil
    end

    test "leaves the trusted run unrestricted" do
      public_entity = create_policy_entity(true)
      private_entity = create_policy_entity(false)

      ids =
        PolicyModule1
        |> Query.normalize()
        |> run(@policy_mapping)
        |> Enum.map(& &1.id)
        |> Enum.sort()

      assert ids == Enum.sort([public_entity.id, private_entity.id])
    end
  end

  describe "run/3" do
    test "binds membership element placeholders" do
      {_first, _second, third} = create_module_2_entities()

      term = %{Query.normalize(Module2) | filter: [{:b, :in, [{:placeholder, :bound}, 3]}]}

      assert [%{id: id, b: 7}] = run(term, @mapping, %{bound: 7})
      assert id == third.id
    end

    # Constraint options are write-side semantics - a placeholder binding checks the type
    # only, and an out-of-constraint value is a query matching nothing, not an
    # invalid query.
    test "binds placeholder values violating declared constraint options" do
      Module10
      |> Entity.new(count: 5)
      |> create()

      mapping = Mapper.derive!([Module10])
      term = %{Query.normalize(Module10) | filter: [{:count, :==, {:placeholder, :count}}]}

      assert run(term, mapping, %{count: 999}) == []
    end

    test "binds placeholder values with the slot's type" do
      {first, _second, _third} = create_module_2_entities()

      term = %{Query.normalize(Module2) | filter: [{:c, :==, {:placeholder, :search}}]}
      result = run(term, @mapping, %{search: "banana"})

      assert [%{id: id, c: "banana"}] = result
      assert id == first.id
    end

    test "counts matching entities" do
      create_module_2_entities()

      term =
        Module2
        |> filter(a: true)
        |> count()
        |> Query.normalize()

      assert run(term, @mapping) == 2
    end

    test "decodes a to-many include with nested clauses" do
      {first, _second, third} = create_module_2_entities()
      source = create_module_3_entity()

      :ok = add_relationship(Module3, source.id, :a, first.id)
      :ok = add_relationship(Module3, source.id, :a, third.id)

      term =
        Module3
        |> include(:a, fn related_query ->
          related_query
          |> filter(a: true)
          |> order_by(:c)
        end)
        |> Query.normalize()

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
        |> include(:a)
        |> Query.normalize()

      direct_term =
        Module2
        |> filter(id: target.id)
        |> one()
        |> Query.normalize()

      assert [%Module3{a: [embedded]}] = run(embedding_term, @mapping)

      assert embedded.created_at == run(direct_term, @mapping).created_at
      assert embedded.created_at == stamp
    end

    test "decodes a to-one include as a nested entity struct" do
      source = create_module_3_entity()

      term =
        Module3
        |> include(:c)
        |> Query.normalize()

      assert [%Module3{id: id, c: %Module1{} = embedded_entity}] = run(term, @mapping)
      assert id == source.id
      assert embedded_entity.id == source.c_id
      assert %DateTime{} = embedded_entity.created_at
    end

    test "embeds an included row the read policy hides from an acting user" do
      parent =
        PolicyModule2
        |> Entity.new()
        |> DB.create()

      PolicyModule1
      |> Entity.new(parent_id: parent.id, public: true)
      |> DB.create()

      term =
        PolicyModule1
        |> include(:parent)
        |> Query.normalize()

      assert [%{parent: included_parent}] = run(term, @policy_mapping)
      assert included_parent.id == parent.id
    end

    test "decodes an absent optional to-one include as nil" do
      create_module_3_entity()

      term =
        Module3
        |> include(:b)
        |> Query.normalize()

      assert [%{b: nil}] = run(term, @mapping)
    end

    test "defaults not-included relationships to the sentinel" do
      create_module_3_entity()

      term = Query.normalize(Module3)

      assert [%Module3{} = entity] = run(term, @mapping)
      assert entity.a == %NotIncluded{relationship: :a}
      assert entity.b == %NotIncluded{relationship: :b}
      assert entity.c == %NotIncluded{relationship: :c}
    end

    test "filters and orders a to-many include whose target names columns like the join table" do
      source =
        Module9
        |> Entity.new()
        |> create()

      first_target =
        Module8
        |> Entity.new(source_id: 5)
        |> create()

      second_target =
        Module8
        |> Entity.new(source_id: 1)
        |> create()

      :ok = add_relationship(Module9, source.id, :a, first_target.id)
      :ok = add_relationship(Module9, source.id, :a, second_target.id)

      mapping = Mapper.derive!([Module8, Module9])

      term =
        Module9
        |> include(:a, fn related_query ->
          related_query
          |> filter(source_id: {:>=, 2})
          |> order_by(:source_id)
        end)
        |> Query.normalize()

      assert [%Module9{a: [%Module8{source_id: 5}]}] = run(term, mapping)
    end

    test "matches nothing for an empty membership list binding" do
      create_module_2_entities()

      term = %{Query.normalize(Module2) | filter: [{:b, :in, {:placeholder, :ids}}]}

      assert run(term, @mapping, %{ids: []}) == []
    end

    test "filters by a to-one reference field" do
      matching = create_module_3_entity()
      create_module_3_entity()

      term =
        Module3
        |> filter(c_id: matching.c_id)
        |> Query.normalize()

      assert [%Module3{id: id, c_id: c_id}] = run(term, @mapping)
      assert id == matching.id
      assert c_id == matching.c_id
    end

    test "filters by a to-one reference field bound as a placeholder" do
      matching = create_module_3_entity()
      create_module_3_entity()

      term = %{Query.normalize(Module3) | filter: [{:c_id, :==, {:placeholder, :target}}]}

      assert [%Module3{id: id}] = run(term, @mapping, %{target: matching.c_id})
      assert id == matching.id
    end

    test "returns entity structs filtered and ordered" do
      {first, _second, third} = create_module_2_entities()

      term =
        Module2
        |> filter(a: true)
        |> order_by(:c)
        |> Query.normalize()

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
        |> Query.normalize()

      assert run(term, @mapping) == nil
    end

    test "returns the first entity under the total order for single-result queries" do
      {_first, second, _third} = create_module_2_entities()

      term =
        Module2
        |> order_by(:c)
        |> one()
        |> Query.normalize()

      assert %{id: id, c: "apple"} = run(term, @mapping)
      assert id == second.id
    end

    test "raises on a malformed id placeholder value" do
      term = %{Query.normalize(Module2) | filter: [{:id, :==, {:placeholder, :entity_id}}]}

      expected_msg =
        ~s(invalid value "not-a-uuid" for placeholder :entity_id - expected a :uuid value)

      assert_error ArgumentError, expected_msg, fn ->
        run(term, @mapping, %{entity_id: "not-a-uuid"})
      end
    end

    test "raises on a membership binding that is not a list" do
      term = %{Query.normalize(Module2) | filter: [{:b, :in, {:placeholder, :ids}}]}

      expected_msg =
        "non-list value 5 for placeholder :ids - the placeholder binds a membership list"

      assert_error ArgumentError, expected_msg, fn ->
        run(term, @mapping, %{ids: 5})
      end
    end

    test "raises on a membership element of the wrong type" do
      term = %{Query.normalize(Module2) | filter: [{:b, :in, {:placeholder, :ids}}]}

      expected_msg =
        ~s(invalid element "x" in the list for placeholder :ids - expected a :integer value)

      assert_error ArgumentError, expected_msg, fn ->
        run(term, @mapping, %{ids: [1, "x"]})
      end
    end

    test "raises on a missing placeholder value" do
      term = %{Query.normalize(Module2) | filter: [{:c, :==, {:placeholder, :search}}]}

      assert_error ArgumentError, "missing value for placeholder :search", fn ->
        run(term, @mapping)
      end
    end

    test "raises on a nil membership element" do
      term = %{Query.normalize(Module2) | filter: [{:b, :in, {:placeholder, :ids}}]}

      expected_msg =
        "nil element in the list for placeholder :ids - use an explicit nil predicate instead"

      assert_error ArgumentError, expected_msg, fn ->
        run(term, @mapping, %{ids: [1, nil]})
      end
    end

    test "raises on a nil placeholder value" do
      term = %{Query.normalize(Module2) | filter: [{:c, :==, {:placeholder, :search}}]}

      expected_msg = "nil value for placeholder :search - use an explicit nil predicate instead"

      assert_error ArgumentError, expected_msg, fn ->
        run(term, @mapping, %{search: nil})
      end
    end

    test "raises on a placeholder binding with conflicting types" do
      term = %{
        Query.normalize(Module2)
        | filter: [{:b, :==, {:placeholder, :x}}, {:b, :in, {:placeholder, :x}}]
      }

      expected_msg =
        "placeholder :x binds as :integer and {:list, :integer} - rename one of the conflicting variables"

      assert_error ArgumentError, expected_msg, fn ->
        run(term, @mapping, %{x: 5})
      end
    end

    test "raises on a placeholder value of the wrong type" do
      term = %{Query.normalize(Module2) | filter: [{:c, :==, {:placeholder, :search}}]}

      expected_msg = "invalid value 123 for placeholder :search - expected a :string value"

      assert_error ArgumentError, expected_msg, fn ->
        run(term, @mapping, %{search: 123})
      end
    end

    test "raises on an enum placeholder value outside the declared set" do
      term = %{Query.normalize(Module4) | filter: [{:c, :==, {:placeholder, :choice}}]}

      expected_msg = "invalid value :z for placeholder :choice - expected one of [:x, :y]"

      assert_error ArgumentError, expected_msg, fn ->
        run(term, @mapping, %{choice: :z})
      end
    end

    test "raises on an unknown binding name" do
      term = %{Query.normalize(Module2) | filter: [{:c, :==, {:placeholder, :search}}]}

      expected_msg =
        "unknown placeholder :serach in bindings - the query defines placeholders [:search]"

      assert_error ArgumentError, expected_msg, fn ->
        run(term, @mapping, %{search: "x", serach: "y"})
      end
    end
  end
end
