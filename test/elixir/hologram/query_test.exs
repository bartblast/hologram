defmodule Hologram.QueryTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Query

  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module4

  describe "filter/2" do
    test "accepts an explicit equality operator tuple" do
      query = filter(Module2, a: {:==, true})

      assert query.filter == [{:a, :==, true}]
    end

    test "accepts nil as an inequality operand" do
      query = filter(Module2, b: {:!=, nil})

      assert query.filter == [{:b, :!=, nil}]
    end

    test "accepts system attribute names" do
      query = filter(Module2, id: "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f")

      assert query.filter == [{:id, :==, "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f"}]
    end

    test "accumulates repeated filters on the same attribute" do
      query =
        Module2
        |> filter(b: {:>=, 3})
        |> filter(b: {:<, 10})

      assert query.filter == [{:b, :>=, 3}, {:b, :<, 10}]
    end

    test "appends to an already built query term" do
      query =
        Module2
        |> filter(a: true)
        |> filter(b: 123)

      assert query == %{
               cardinality: :set,
               entity: Module2,
               filter: [{:a, :==, true}, {:b, :==, 123}],
               include: %{},
               limit: nil,
               offset: nil,
               order_by: []
             }
    end

    test "builds a membership triple from a bare list" do
      query = filter(Module2, c: ["x", "y"])

      assert query.filter == [{:c, :in, ["x", "y"]}]
    end

    test "builds a membership triple from an operator tuple" do
      query = filter(Module2, b: {:in, [1, 2]})

      assert query.filter == [{:b, :in, [1, 2]}]
    end

    test "builds a negated membership triple" do
      query = filter(Module2, b: {:not_in, [1, 2]})

      assert query.filter == [{:b, :not_in, [1, 2]}]
    end

    test "builds an inequality triple" do
      query = filter(Module2, c: {:!=, "x"})

      assert query.filter == [{:c, :!=, "x"}]
    end

    test "builds an ordering triple for a date attribute" do
      query = filter(Module4, a: {:>, ~D[2026-01-01]})

      assert query.filter == [{:a, :>, ~D[2026-01-01]}]
    end

    test "builds an ordering triple for a datetime attribute" do
      query = filter(Module4, b: {:<=, ~U[2026-01-01 12:00:00Z]})

      assert query.filter == [{:b, :<=, ~U[2026-01-01 12:00:00Z]}]
    end

    test "builds an ordering triple for a float attribute" do
      query = filter(Module4, d: {:<, 8.5})

      assert query.filter == [{:d, :<, 8.5}]
    end

    test "builds an ordering triple for a system timestamp" do
      query = filter(Module2, created_at: {:>, ~U[2026-01-01 12:00:00Z]})

      assert query.filter == [{:created_at, :>, ~U[2026-01-01 12:00:00Z]}]
    end

    test "builds an ordering triple for an integer attribute" do
      query = filter(Module2, b: {:>=, 3})

      assert query.filter == [{:b, :>=, 3}]
    end

    test "builds conjunction triples from a list of operator tuples" do
      query = filter(Module2, b: [{:>=, 3}, {:<, 10}])

      assert query.filter == [{:b, :>=, 3}, {:b, :<, 10}]
    end

    test "expands a range passed to the membership operator" do
      query = filter(Module2, b: {:in, 3..10})

      assert query.filter == [{:b, :>=, 3}, {:b, :<=, 10}]
    end

    test "expands an integer range into inclusive bound triples" do
      query = filter(Module2, b: 3..10)

      assert query.filter == [{:b, :>=, 3}, {:b, :<=, 10}]
    end

    test "keeps predicates in the given order" do
      query = filter(Module2, c: "abc", a: false)

      assert query.filter == [{:c, :==, "abc"}, {:a, :==, false}]
    end

    test "starts a query term from an entity type module" do
      assert filter(Module2, a: true) == %{
               cardinality: :set,
               entity: Module2,
               filter: [{:a, :==, true}],
               include: %{},
               limit: nil,
               offset: nil,
               order_by: []
             }
    end

    test "treats nil as a regular equality value" do
      query = filter(Module2, b: nil)

      assert query.filter == [{:b, :==, nil}]
    end

    test "raises on a descending range" do
      expected_msg =
        "stepped range 10..3//-1 for attribute :b is not supported - membership ranges use step 1"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, b: 10..3//-1)
      end
    end

    test "raises on a list operand for an equality operator" do
      expected_msg = "invalid operand [1, 2] for operator :== on attribute :b"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, b: {:==, [1, 2]})
      end
    end

    test "raises on a membership list holding an operator tuple" do
      expected_msg =
        "invalid membership list element {:>=, 3} for attribute :b - membership lists hold plain values"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, b: {:in, [1, {:>=, 3}]})
      end
    end

    test "raises on a mixed filter list" do
      expected_msg =
        "invalid filter list [1, {:>=, 3}] for attribute :b - use either a membership list of plain values or a list of operator tuples"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, b: [1, {:>=, 3}])
      end
    end

    test "raises on a membership list holding nil" do
      expected_msg =
        "nil in the membership list for attribute :b - use an equality predicate to match nil"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, b: [nil, 1])
      end
    end

    test "raises on a nil ordering operand" do
      expected_msg = "invalid operand nil for operator :>= on attribute :b"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, b: {:>=, nil})
      end
    end

    test "raises on a non-entity module query" do
      expected_msg =
        ~s(String is not an entity type module or a query term - a query starts from a module with the "use Hologram.Entity" directive)

      assert_error ArgumentError, expected_msg, fn ->
        filter(String, a: true)
      end
    end

    test "raises on a non-list membership operand" do
      expected_msg = "operator :in on attribute :b requires a list operand, got: 5"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, b: {:in, 5})
      end
    end

    test "raises on a non-module query" do
      expected_msg =
        ~s(123 is not an entity type module or a query term - a query starts from a module with the "use Hologram.Entity" directive)

      assert_error ArgumentError, expected_msg, fn ->
        filter(123, a: true)
      end
    end

    test "raises on a predicate naming a relationship" do
      expected_msg =
        ":c is a relationship in Hologram.Test.Fixtures.Entity.Module3 - only attributes can be filtered"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module3, c: "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f")
      end
    end

    test "raises on a predicate naming an unknown attribute" do
      expected_msg =
        "unknown attribute :x in Hologram.Test.Fixtures.Entity.Module2 - known attributes: :a, :b, :c, :created_at, :id, :updated_at"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, x: 1)
      end
    end

    test "raises on a range on a non-integer attribute" do
      expected_msg =
        "range 3..10 requires an integer attribute - attribute :d in Hologram.Test.Fixtures.Entity.Module4 has type :float"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module4, d: 3..10)
      end
    end

    test "raises on a stepped range" do
      expected_msg =
        "stepped range 3..10//2 for attribute :b is not supported - membership ranges use step 1"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, b: 3..10//2)
      end
    end

    test "raises on an empty filter list" do
      expected_msg = "filter list for attribute :b must not be empty"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, b: [])
      end
    end

    test "raises on an empty membership list" do
      expected_msg = "membership list for attribute :b must not be empty"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, b: {:in, []})
      end
    end

    test "raises on an empty range" do
      expected_msg = "range 5..3//1 for attribute :b is empty - it would match nothing"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, b: 5..3//1)
      end
    end

    test "raises on an invalid tuple filter value" do
      expected_msg = "invalid filter value {1, 2, 3} for attribute :b"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, b: {1, 2, 3})
      end
    end

    test "raises on an ordering comparison on a string attribute" do
      expected_msg =
        "operator :>= requires a numeric or temporal attribute - attribute :c in Hologram.Test.Fixtures.Entity.Module2 has type :string"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, c: {:>=, "x"})
      end
    end

    test "raises on an ordering comparison on an enum attribute" do
      expected_msg =
        "operator :> requires a numeric or temporal attribute - attribute :c in Hologram.Test.Fixtures.Entity.Module4 has type :enum"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module4, c: {:>, :x})
      end
    end

    test "raises on an ordering comparison on the id attribute" do
      expected_msg =
        "operator :< requires a numeric or temporal attribute - attribute :id in Hologram.Test.Fixtures.Entity.Module2 has type :uuid"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, id: {:<, "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f"})
      end
    end

    test "raises on an unknown operator" do
      expected_msg =
        "unknown operator :like in the filter predicate for attribute :b - supported operators: :!=, :<, :<=, :==, :>, :>=, :in, :not_in"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, b: {:like, "x"})
      end
    end

    test "raises on non-keyword predicates" do
      expected_msg = "filter predicates must be a keyword list, got: [:a]"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, [:a])
      end
    end
  end
end
