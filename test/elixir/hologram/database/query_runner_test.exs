defmodule Hologram.Database.QueryRunnerTest do
  use Hologram.Test.DatabaseCase, async: true
  use Hologram.Query

  import Hologram.Database.EntityOperations, only: [add_relationship: 4, create: 1]
  import Hologram.Database.QueryRunner

  alias Hologram.Database.Mapper
  alias Hologram.Entity
  alias Hologram.Entity.NotIncluded
  alias Hologram.Query
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3

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

    test "raises on a missing param value" do
      term = %{Query.normalize(Module2) | filter: [{:c, :==, {:param, :search}}]}

      assert_error ArgumentError, "missing value for param :search", fn ->
        run(term, @mapping)
      end
    end

    test "raises on a nil param value" do
      term = %{Query.normalize(Module2) | filter: [{:c, :==, {:param, :search}}]}

      expected_msg = "nil value for param :search - use an explicit nil predicate instead"

      assert_error ArgumentError, expected_msg, fn ->
        run(term, @mapping, %{search: nil})
      end
    end
  end
end
