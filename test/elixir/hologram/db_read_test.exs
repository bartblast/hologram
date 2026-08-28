defmodule Hologram.DBReadTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.Query
  import Hologram.Test, only: [as_user: 2]

  alias Hologram.Auth
  alias Hologram.DB
  alias Hologram.Entity
  alias Hologram.Query.Placeholder
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Policy.Module1, as: PolicyModule1
  alias Hologram.Test.Fixtures.Policy.Module2, as: PolicyModule2
  alias Hologram.Test.Fixtures.Policy.Module3, as: PolicyModule3

  defp create_module_2_entity(values) do
    values
    |> Module2.new()
    |> DB.create!()
  end

  defp create_policy_module_2_entity do
    DB.create!(PolicyModule2.new())
  end

  defp create_user(email) do
    %{email: email}
    |> Module14.new()
    |> DB.create!()
  end

  describe "read/1" do
    test "counts only the rows the acting user may read" do
      user = create_user("db_read_count@example.com")
      granted_entity = create_policy_module_2_entity()
      create_policy_module_2_entity()

      Auth.grant_role(user, granted_entity, :member)

      count =
        as_user(user, fn ->
          PolicyModule2
          |> count()
          |> DB.read()
        end)

      assert count == 1
    end

    test "filters an include's rows by the target type's read policies" do
      user = create_user("db_read_include@example.com")

      public_child =
        %{public: true}
        |> PolicyModule1.new()
        |> DB.create!()

      private_child =
        %{public: false}
        |> PolicyModule1.new()
        |> DB.create!()

      source = DB.create!(PolicyModule3.new())

      source
      |> add_relationship(:children, public_child.id)
      |> add_relationship(:children, private_child.id)
      |> DB.update!()

      results =
        as_user(user, fn ->
          PolicyModule3
          |> include(:children)
          |> DB.read()
        end)

      assert [%PolicyModule3{children: [%PolicyModule1{id: child_id}]}] = results
      assert child_id == public_child.id
    end

    test "filters the rows by the acting user's read policies" do
      user = create_user("db_read_filter@example.com")
      granted_entity = create_policy_module_2_entity()
      create_policy_module_2_entity()

      Auth.grant_role(user, granted_entity, :member)

      results = as_user(user, fn -> DB.read(PolicyModule2) end)

      assert [%PolicyModule2{id: id}] = results
      assert id == granted_entity.id
    end

    test "reads a set query and returns entity structs" do
      create_module_2_entity(a: true, c: "bbb")
      create_module_2_entity(a: false, c: "aaa")

      results =
        Module2
        |> order_by(:c)
        |> DB.read()

      assert [%Module2{c: "aaa"}, %Module2{c: "bbb"}] = results
    end

    test "reads a bare entity type as the whole set" do
      create_module_2_entity(a: true, c: "some text")

      assert [%Module2{c: "some text"}] = DB.read(Module2)
    end

    test "reads a single-result query" do
      created_entity = create_module_2_entity(a: true, c: "some text")

      found_entity =
        Module2
        |> filter(id: created_entity.id)
        |> one()
        |> DB.read()

      assert found_entity.id == created_entity.id

      missing_entity =
        Module2
        |> filter(id: Entity.generate_id())
        |> one()
        |> DB.read()

      assert missing_entity == nil
    end

    test "reads a single-result query as nil for a row the acting user may not read" do
      user = create_user("db_read_single@example.com")
      entity = create_policy_module_2_entity()

      hidden_entity =
        as_user(user, fn ->
          PolicyModule2
          |> filter(id: entity.id)
          |> one()
          |> DB.read()
        end)

      assert hidden_entity == nil

      Auth.grant_role(user, entity, :member)

      readable_entity =
        as_user(user, fn ->
          PolicyModule2
          |> filter(id: entity.id)
          |> one()
          |> DB.read()
        end)

      assert readable_entity.id == entity.id
    end

    test "reads a counting query" do
      create_module_2_entity(a: true, c: "x")
      create_module_2_entity(a: true, c: "y")
      create_module_2_entity(a: false, c: "z")

      count =
        Module2
        |> filter(a: true)
        |> count()
        |> DB.read()

      assert count == 2
    end

    test "reads a trusted query raw under an acting user" do
      user = create_user("db_read_trusted@example.com")
      create_policy_module_2_entity()
      create_policy_module_2_entity()

      trusted_results =
        as_user(user, fn ->
          PolicyModule2
          |> trust()
          |> DB.read()
        end)

      untrusted_results = as_user(user, fn -> DB.read(PolicyModule2) end)

      assert length(trusted_results) == 2
      assert untrusted_results == []
    end

    # Pins that no actor is the trusted tier rather than an anonymous session: the anonymous
    # semantics drop actor-gated rules, so PolicyModule2's "allow :read, to: :member" would
    # grant nothing and this would read [].
    test "reads every row without an acting user" do
      create_policy_module_2_entity()
      create_policy_module_2_entity()

      assert length(DB.read(PolicyModule2)) == 2
    end

    test "raises on a query term containing placeholders" do
      expected_msg =
        "cannot read a query term containing placeholders - placeholder :min_b has no value: directly executed queries embed concrete runtime values, placeholders exist only in compiler-registered queries"

      assert_error ArgumentError, expected_msg, fn ->
        Module2
        |> filter(b: {:>=, %Placeholder{name: :min_b}})
        |> DB.read()
      end
    end

    test "raises on a query term ordered by a placeholder" do
      expected_msg =
        "cannot read a query term containing placeholders - placeholder :sort has no value: directly executed queries embed concrete runtime values, placeholders exist only in compiler-registered queries"

      assert_error ArgumentError, expected_msg, fn ->
        Module2
        |> order_by(%Placeholder{name: :sort})
        |> DB.read()
      end
    end
  end

  describe "read/2" do
    test "reads a policied row without an acting user" do
      entity = create_policy_module_2_entity()

      assert DB.read(PolicyModule2, entity.id) == entity
    end

    test "reads nil for a row the acting user may not read" do
      user = create_user("db_read_by_id_hidden@example.com")
      entity = create_policy_module_2_entity()

      assert as_user(user, fn -> DB.read(PolicyModule2, entity.id) end) == nil
    end

    test "reads nil when no row has the id" do
      create_module_2_entity(a: true, c: "some text")

      assert DB.read(Module2, Entity.generate_id()) == nil
    end

    test "reads the row" do
      entity = create_module_2_entity(a: true, c: "some text")

      assert DB.read(Module2, entity.id) == entity
    end

    test "reads the row the acting user may read" do
      user = create_user("db_read_by_id_readable@example.com")
      entity = create_policy_module_2_entity()

      Auth.grant_role(user, entity, :member)

      assert as_user(user, fn -> DB.read(PolicyModule2, entity.id) end) == entity
    end

    test "raises on a non-canonical id" do
      user = create_user("db_read_by_id_invalid_id@example.com")

      expected_msg =
        ~s(invalid id "nope" - entity ids are canonical lowercase 8-4-4-4-12 UUID strings)

      assert_error ArgumentError, expected_msg, fn -> DB.read(PolicyModule2, "nope") end

      assert_error ArgumentError, expected_msg, fn ->
        as_user(user, fn -> DB.read(PolicyModule2, "nope") end)
      end
    end

    # A term reaches both branches the same way or it reaches neither: before this refusal the
    # no-actor branch raised KeyError and the acting-user branch answered nil, ignoring the mark
    # the term carries.
    test "raises on a query term" do
      user = create_user("db_read_by_id_term@example.com")
      entity = create_policy_module_2_entity()
      term = trust(PolicyModule2)

      expected_msg =
        "#{inspect(term)} is not an entity type module - a by-id read takes the entity type, a query term is read with read/1"

      assert_error ArgumentError, expected_msg, fn -> DB.read(term, entity.id) end

      assert_error ArgumentError, expected_msg, fn ->
        as_user(user, fn -> DB.read(term, entity.id) end)
      end
    end
  end
end
