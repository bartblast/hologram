defmodule Hologram.DB.QueryRunnerTest do
  use Hologram.Test.DatabaseCase, async: true
  use Hologram.Query

  import Hologram.DB.EntityOperations, only: [add_relationship: 4, create: 1]
  import Hologram.DB.QueryRunner

  alias Hologram.DB.Mapper
  alias Hologram.Entity
  alias Hologram.Entity.NotIncluded
  alias Hologram.Query
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module10
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module4
  alias Hologram.Test.Fixtures.Entity.Module8
  alias Hologram.Test.Fixtures.Entity.Module9

  @mapping Mapper.derive!([Module1, Module2, Module3])

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

  describe "run/3" do
    test "binds membership element params" do
      {_first, _second, third} = create_module_2_entities()

      term = %{Query.normalize(Module2) | filter: [{:b, :in, [{:param, :bound}, 3]}]}

      assert [%{id: id, b: 7}] = run(term, @mapping, %{bound: 7})
      assert id == third.id
    end

    # Constraint options are write-side semantics - a param binding checks the type
    # only, and an out-of-constraint value is a query matching nothing, not an
    # invalid query.
    test "binds param values violating declared constraint options" do
      Module10
      |> Entity.new(count: 5)
      |> create()

      mapping = Mapper.derive!([Module10])
      term = %{Query.normalize(Module10) | filter: [{:count, :==, {:param, :count}}]}

      assert run(term, mapping, %{count: 999}) == []
    end

    test "binds param values with the slot's type" do
      {first, _second, _third} = create_module_2_entities()

      term = %{Query.normalize(Module2) | filter: [{:c, :==, {:param, :search}}]}
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

      term = %{Query.normalize(Module2) | filter: [{:b, :in, {:param, :ids}}]}

      assert run(term, @mapping, %{ids: []}) == []
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

    test "raises on a malformed id param value" do
      term = %{Query.normalize(Module2) | filter: [{:id, :==, {:param, :entity_id}}]}

      expected_msg = ~s(invalid value "not-a-uuid" for param :entity_id - expected a :uuid value)

      assert_error ArgumentError, expected_msg, fn ->
        run(term, @mapping, %{entity_id: "not-a-uuid"})
      end
    end

    test "raises on a membership binding that is not a list" do
      term = %{Query.normalize(Module2) | filter: [{:b, :in, {:param, :ids}}]}

      expected_msg = "non-list value 5 for param :ids - the param binds a membership list"

      assert_error ArgumentError, expected_msg, fn ->
        run(term, @mapping, %{ids: 5})
      end
    end

    test "raises on a membership element of the wrong type" do
      term = %{Query.normalize(Module2) | filter: [{:b, :in, {:param, :ids}}]}

      expected_msg =
        ~s(invalid element "x" in the list for param :ids - expected a :integer value)

      assert_error ArgumentError, expected_msg, fn ->
        run(term, @mapping, %{ids: [1, "x"]})
      end
    end

    test "raises on a missing param value" do
      term = %{Query.normalize(Module2) | filter: [{:c, :==, {:param, :search}}]}

      assert_error ArgumentError, "missing value for param :search", fn ->
        run(term, @mapping)
      end
    end

    test "raises on a nil membership element" do
      term = %{Query.normalize(Module2) | filter: [{:b, :in, {:param, :ids}}]}

      expected_msg =
        "nil element in the list for param :ids - use an explicit nil predicate instead"

      assert_error ArgumentError, expected_msg, fn ->
        run(term, @mapping, %{ids: [1, nil]})
      end
    end

    test "raises on a nil param value" do
      term = %{Query.normalize(Module2) | filter: [{:c, :==, {:param, :search}}]}

      expected_msg = "nil value for param :search - use an explicit nil predicate instead"

      assert_error ArgumentError, expected_msg, fn ->
        run(term, @mapping, %{search: nil})
      end
    end

    test "raises on a param binding with conflicting types" do
      term = %{
        Query.normalize(Module2)
        | filter: [{:b, :==, {:param, :x}}, {:b, :in, {:param, :x}}]
      }

      expected_msg =
        "param :x binds as :integer and {:list, :integer} - rename one of the conflicting variables"

      assert_error ArgumentError, expected_msg, fn ->
        run(term, @mapping, %{x: 5})
      end
    end

    test "raises on a param value of the wrong type" do
      term = %{Query.normalize(Module2) | filter: [{:c, :==, {:param, :search}}]}

      expected_msg = "invalid value 123 for param :search - expected a :string value"

      assert_error ArgumentError, expected_msg, fn ->
        run(term, @mapping, %{search: 123})
      end
    end

    test "raises on an enum param value outside the declared set" do
      term = %{Query.normalize(Module4) | filter: [{:c, :==, {:param, :choice}}]}

      expected_msg = "invalid value :z for param :choice - expected one of [:x, :y]"

      assert_error ArgumentError, expected_msg, fn ->
        run(term, @mapping, %{choice: :z})
      end
    end

    test "raises on an unknown binding name" do
      term = %{Query.normalize(Module2) | filter: [{:c, :==, {:param, :search}}]}

      expected_msg = "unknown param :serach in bindings - the query defines params [:search]"

      assert_error ArgumentError, expected_msg, fn ->
        run(term, @mapping, %{search: "x", serach: "y"})
      end
    end
  end
end
