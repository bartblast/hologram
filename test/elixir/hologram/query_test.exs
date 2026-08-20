defmodule Hologram.QueryTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Query

  alias Hologram.Query.Param
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module4
  alias Hologram.Test.Fixtures.Entity.Module5

  defp base_term(entity_type) do
    %{
      cardinality: :set,
      entity: entity_type,
      filter: [],
      include: %{},
      limit: nil,
      offset: nil,
      order_by: []
    }
  end

  describe "count/1" do
    test "composes with other stages" do
      query =
        Module2
        |> filter(a: true)
        |> count()

      assert query.cardinality == :count
      assert query.filter == [{:a, :==, true}]
    end

    test "marks the query as counting" do
      assert count(Module2) == %{
               cardinality: :count,
               entity: Module2,
               filter: [],
               include: %{},
               limit: nil,
               offset: nil,
               order_by: []
             }
    end

    test "raises when cardinality is already marked" do
      expected_msg = "cardinality is already set to :one"

      assert_error ArgumentError, expected_msg, fn ->
        Module2
        |> one()
        |> count()
      end
    end
  end

  describe "filter/2" do
    test "accepts a param sentinel as a bare equality value" do
      query = filter(Module2, b: %Param{name: :bound})

      assert query.filter == [{:b, :==, {:param, :bound}}]
    end

    test "accepts a param sentinel as a membership list element" do
      query = filter(Module2, b: [%Param{name: :bound}, 1])

      assert query.filter == [{:b, :in, [{:param, :bound}, 1]}]
    end

    test "accepts a param sentinel as a membership operand" do
      query = filter(Module2, b: {:in, %Param{name: :ids}})

      assert query.filter == [{:b, :in, {:param, :ids}}]
    end

    test "accepts a param sentinel as a membership operator element" do
      query = filter(Module2, b: {:in, [%Param{name: :bound}, 1]})

      assert query.filter == [{:b, :in, [{:param, :bound}, 1]}]
    end

    test "accepts a param sentinel in an inequality operator tuple" do
      query = filter(Module2, c: {:!=, %Param{name: :search}})

      assert query.filter == [{:c, :!=, {:param, :search}}]
    end

    test "accepts a param sentinel in an ordering operator tuple" do
      query = filter(Module2, b: {:>=, %Param{name: :min}})

      assert query.filter == [{:b, :>=, {:param, :min}}]
    end

    test "accepts an explicit equality operator tuple" do
      query = filter(Module2, a: {:==, true})

      assert query.filter == [{:a, :==, true}]
    end

    test "accepts nil as an inequality operand" do
      query = filter(Module2, b: {:!=, nil})

      assert query.filter == [{:b, :!=, nil}]
    end

    test "accepts nil in membership lists" do
      query = filter(Module2, b: [nil, 1])

      assert query.filter == [{:b, :in, [nil, 1]}]
    end

    test "accepts system attribute names" do
      query = filter(Module2, id: "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f")

      assert query.filter == [{:id, :==, "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f"}]
    end

    test "accepts to-one reference field names" do
      query = filter(Module3, c_id: "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f")

      assert query.filter == [{:c_id, :==, "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f"}]
    end

    test "accepts a membership list on a to-one reference field" do
      query = filter(Module3, b_id: [nil, "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f"])

      assert query.filter == [{:b_id, :in, [nil, "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f"]}]
    end

    test "accepts a param sentinel on a to-one reference field" do
      query = filter(Module3, c_id: %Param{name: :owner})

      assert query.filter == [{:c_id, :==, {:param, :owner}}]
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

    test "raises on a param ordering comparison on a string attribute" do
      expected_msg =
        "operator :>= requires a numeric or temporal attribute - attribute :c in Hologram.Test.Fixtures.Entity.Module2 has type :string"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, c: {:>=, %Param{name: :min}})
      end
    end

    test "raises on a predicate naming a to-one relationship" do
      expected_msg =
        ":c is a relationship in Hologram.Test.Fixtures.Entity.Module3 - only attributes can be filtered - filter its reference via :c_id"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module3, c: "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f")
      end
    end

    test "raises on a predicate naming a to-many relationship" do
      expected_msg =
        ":a is a relationship in Hologram.Test.Fixtures.Entity.Module3 - only attributes can be filtered"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module3, a: "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f")
      end
    end

    test "raises on an ordering comparison on a to-one reference field" do
      expected_msg =
        "operator :>= requires a numeric or temporal attribute - attribute :c_id in Hologram.Test.Fixtures.Entity.Module3 has type :uuid"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module3, c_id: {:>=, "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f"})
      end
    end

    test "raises on a predicate naming an unknown attribute" do
      expected_msg =
        "unknown attribute :x in Hologram.Test.Fixtures.Entity.Module2 - known attributes: :a, :b, :c, :created_at, :id, :updated_at"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, x: 1)
      end
    end

    test "raises on an unknown attribute listing to-one reference fields among the known names" do
      expected_msg =
        "unknown attribute :x in Hologram.Test.Fixtures.Entity.Module3 - known attributes: :b_id, :c_id, :created_at, :id, :updated_at"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module3, x: 1)
      end
    end

    test "raises on a range inside a membership operand" do
      expected_msg =
        "invalid membership list element 1..3 for attribute :b - membership lists hold plain values"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, b: {:in, [1..3, 5]})
      end
    end

    test "raises on a range on a non-integer attribute" do
      expected_msg =
        "range 3..10 requires an integer attribute - attribute :d in Hologram.Test.Fixtures.Entity.Module4 has type :float"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module4, d: 3..10)
      end
    end

    test "raises on a range operand for an equality operator" do
      expected_msg = "invalid operand 1..5 for operator :== on attribute :b"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, b: {:==, 1..5})
      end
    end

    test "raises on a range operand for an ordering comparison" do
      expected_msg = "invalid operand 1..5 for operator :> on attribute :b"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, b: {:>, 1..5})
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

    test "raises on an unknown operator with a param operand" do
      expected_msg =
        "unknown operator :like in the filter predicate for attribute :b - supported operators: :!=, :<, :<=, :==, :>, :>=, :in, :not_in"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, b: {:like, %Param{name: :x}})
      end
    end

    test "raises on non-keyword predicates" do
      expected_msg = "filter predicates must be a keyword list, got: [:a]"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, [:a])
      end
    end
  end

  describe "include/3" do
    test "accepts a sub-builder as a spec value" do
      query = include(Module3, a: &filter(&1, a: true))

      assert query.include == %{a: %{base_term(Module2) | filter: [{:a, :==, true}]}}
    end

    test "accumulates multiple includes" do
      query =
        Module3
        |> include(:a)
        |> include(:b)

      assert query.include == %{a: base_term(Module2), b: base_term(Module2)}
    end

    test "embeds a to-many relationship" do
      assert include(Module3, :a) == %{
               cardinality: :set,
               entity: Module3,
               filter: [],
               include: %{a: base_term(Module2)},
               limit: nil,
               offset: nil,
               order_by: []
             }
    end

    test "embeds a to-one relationship" do
      query = include(Module3, :c)

      assert query.include == %{c: base_term(Module1)}
    end

    test "includes several relationships from a list spec" do
      query = include(Module3, [:a, :b])

      assert query.include == %{a: base_term(Module2), b: base_term(Module2)}
    end

    test "mixes flat and nested entries" do
      query = include(Module5, [:b, a: :a])

      assert query.include == %{
               a: %{base_term(Module3) | include: %{a: base_term(Module2)}},
               b: base_term(Module5)
             }
    end

    test "nests a list spec" do
      query = include(Module5, a: [:a, :b])

      assert query.include == %{
               a: %{base_term(Module3) | include: %{a: base_term(Module2), b: base_term(Module2)}}
             }
    end

    test "nests includes through the sub-builder" do
      query = include(Module5, :a, &include(&1, :a))

      assert query.include == %{a: %{base_term(Module3) | include: %{a: base_term(Module2)}}}
    end

    test "nests traversal from a keyword spec" do
      query = include(Module5, a: :a)

      assert query.include == %{a: %{base_term(Module3) | include: %{a: base_term(Module2)}}}
    end

    test "refines a to-many include with a sub-builder" do
      query =
        include(Module3, :a, fn related_query ->
          related_query
          |> filter(a: false)
          |> order_by(:c)
        end)

      expected_sub_term = %{
        base_term(Module2)
        | filter: [{:a, :==, false}],
          order_by: [{:c, :asc}]
      }

      assert query.include == %{a: expected_sub_term}
    end

    test "raises on a duplicate include" do
      expected_msg = "relationship :a is already included"

      assert_error ArgumentError, expected_msg, fn ->
        Module3
        |> include(:a)
        |> include(:a)
      end
    end

    test "raises on a non-function sub-builder" do
      expected_msg =
        "include sub-builder for relationship :a must be a one-argument function, got: 5"

      assert_error ArgumentError, expected_msg, fn ->
        include(Module3, :a, wrap_term(5))
      end
    end

    test "raises on a separate sub-builder with a shape spec" do
      expected_msg =
        "an include shape spec takes no separate sub-builder - nest it in the spec as a {name, sub_builder} pair"

      assert_error ArgumentError, expected_msg, fn ->
        include(Module3, wrap_term([:a]), fn related_query -> related_query end)
      end
    end

    test "raises on a sub-builder returning a different entity's term" do
      expected_msg =
        "include sub-builder for relationship :a must return a query term for Hologram.Test.Fixtures.Entity.Module2 - got a query term for Hologram.Test.Fixtures.Entity.Module1"

      assert_error ArgumentError, expected_msg, fn ->
        include(Module3, :a, fn _related_query -> filter(Module1, []) end)
      end
    end

    test "raises on a sub-builder returning a non-term" do
      expected_msg =
        "include sub-builder for relationship :a must return a query term for Hologram.Test.Fixtures.Entity.Module2, got: 123"

      assert_error ArgumentError, expected_msg, fn ->
        include(Module3, :a, fn _related_query -> 123 end)
      end
    end

    # The relationship declaration already says how many entities are embedded, so a sub-term
    # marking a cardinality of its own would be saying something the shape cannot honour.
    test "raises on a sub-term carrying a cardinality marker" do
      expected_msg =
        "include sub-terms take no cardinality marker - the relationship declaration governs cardinality"

      assert_error ArgumentError, expected_msg, fn ->
        include(Module3, :a, &count/1)
      end
    end

    test "raises on an attribute name" do
      expected_msg =
        ":a is an attribute in Hologram.Test.Fixtures.Entity.Module2 - only relationships can be included"

      assert_error ArgumentError, expected_msg, fn ->
        include(Module2, :a)
      end
    end

    test "raises on an empty include spec" do
      expected_msg = "include spec must not be empty"

      assert_error ArgumentError, expected_msg, fn ->
        include(Module3, wrap_term([]))
      end
    end

    test "raises on an invalid include spec" do
      expected_msg = "include spec must be a relationship name or a shape list, got: 123"

      assert_error ArgumentError, expected_msg, fn ->
        include(Module3, wrap_term(123))
      end
    end

    test "raises on an invalid include spec entry" do
      expected_msg =
        "invalid include spec entry 123 - use a relationship name, a {name, spec} pair, or a {name, sub_builder} pair"

      assert_error ArgumentError, expected_msg, fn ->
        include(Module3, [123])
      end
    end

    test "raises on an unknown relationship" do
      expected_msg =
        "unknown relationship :x in Hologram.Test.Fixtures.Entity.Module3 - known relationships: :a, :b, :c"

      assert_error ArgumentError, expected_msg, fn ->
        include(Module3, :x)
      end
    end

    test "raises on clauses on a to-one include" do
      expected_msg =
        "to-one relationship :b takes no clauses - clauses apply to to-many includes"

      assert_error ArgumentError, expected_msg, fn ->
        include(Module3, :b, &filter(&1, a: true))
      end
    end

    test "raises on excessive traversal depth" do
      expected_msg = "including :b exceeds the traversal depth limit of 2 levels"

      assert_error ArgumentError, expected_msg, fn ->
        include(Module5, :b, fn level_1 ->
          include(level_1, :b, fn level_2 ->
            include(level_2, :b)
          end)
        end)
      end
    end
  end

  describe "limit/2" do
    test "accepts zero" do
      query = limit(Module2, 0)

      assert query.limit == 0
    end

    test "composes with other stages" do
      query =
        Module2
        |> filter(a: true)
        |> limit(50)

      assert query.filter == [{:a, :==, true}]
      assert query.limit == 50
    end

    test "sets the limit" do
      assert limit(Module2, 50) == %{
               cardinality: :set,
               entity: Module2,
               filter: [],
               include: %{},
               limit: 50,
               offset: nil,
               order_by: []
             }
    end

    test "raises on a negative limit" do
      expected_msg = "limit must be a non-negative integer, got: -5"

      assert_error ArgumentError, expected_msg, fn ->
        limit(Module2, -5)
      end
    end

    test "raises on a non-integer limit" do
      expected_msg = "limit must be a non-negative integer, got: 5.0"

      assert_error ArgumentError, expected_msg, fn ->
        limit(Module2, wrap_term(5.0))
      end
    end

    test "raises when the limit is already set" do
      expected_msg = "limit is already set to 50"

      assert_error ArgumentError, expected_msg, fn ->
        Module2
        |> limit(50)
        |> limit(100)
      end
    end
  end

  describe "normalize/1" do
    test "appends an ascending id tiebreaker to orderings" do
      query =
        Module2
        |> order_by(:c)
        |> normalize()

      assert query.order_by == [{:c, :asc}, {:id, :asc}]
    end

    test "defaults an empty ordering to the id order" do
      assert normalize(Module2) == %{
               cardinality: :set,
               entity: Module2,
               filter: [],
               include: %{},
               limit: nil,
               offset: nil,
               order_by: [{:id, :asc}]
             }
    end

    test "drops the ordering from counting queries" do
      query =
        Module2
        |> order_by(:c)
        |> count()
        |> normalize()

      assert query.order_by == []
    end

    test "is idempotent" do
      normalized =
        Module3
        |> filter(id: "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f")
        |> include(:a)
        |> order_by(:created_at)
        |> normalize()

      assert normalize(normalized) == normalized
    end

    test "leaves orderings already keyed by id untouched" do
      query =
        Module2
        |> order_by(id: :desc)
        |> normalize()

      assert query.order_by == [{:id, :desc}]
    end

    test "normalizes includes nested under a to-one include" do
      query =
        Module5
        |> include(a: :a)
        |> normalize()

      nested_sub_term = query.include.a.include.a

      assert query.include.a.order_by == []
      assert nested_sub_term.order_by == [{:id, :asc}]
    end

    test "normalizes to-many sub-terms" do
      query =
        Module3
        |> include(:a, &filter(&1, c: "x", a: true))
        |> normalize()

      assert query.include.a.filter == [{:a, :==, true}, {:c, :==, "x"}]
      assert query.include.a.order_by == [{:id, :asc}]
    end

    test "skips ordering for to-one includes" do
      query =
        Module3
        |> include(:c)
        |> normalize()

      assert query.include.c.order_by == []
    end

    test "sorts filter predicates canonically" do
      query =
        Module2
        |> filter(c: "x", a: true)
        |> normalize()

      assert query.filter == [{:a, :==, true}, {:c, :==, "x"}]
    end
  end

  describe "offset/2" do
    test "sets the offset" do
      assert offset(Module2, 20) == %{
               cardinality: :set,
               entity: Module2,
               filter: [],
               include: %{},
               limit: nil,
               offset: 20,
               order_by: []
             }
    end

    test "raises on a negative offset" do
      expected_msg = "offset must be a non-negative integer, got: -5"

      assert_error ArgumentError, expected_msg, fn ->
        offset(Module2, -5)
      end
    end
  end

  describe "one/1" do
    test "composes with other stages" do
      query =
        Module2
        |> filter(a: true)
        |> one()

      assert query.cardinality == :one
      assert query.filter == [{:a, :==, true}]
    end

    test "marks the query as single-result" do
      assert one(Module2) == %{
               cardinality: :one,
               entity: Module2,
               filter: [],
               include: %{},
               limit: nil,
               offset: nil,
               order_by: []
             }
    end

    test "raises on a cardinality marker in an include sub-term" do
      expected_msg =
        "include sub-terms take no cardinality marker - the relationship declaration governs cardinality"

      assert_error ArgumentError, expected_msg, fn ->
        include(Module3, :b, &one/1)
      end
    end

    test "raises when cardinality is already marked" do
      expected_msg = "cardinality is already set to :one"

      assert_error ArgumentError, expected_msg, fn ->
        Module2
        |> one()
        |> one()
      end
    end
  end

  describe "order_by/2" do
    test "accepts a keyword spec with directions" do
      query = order_by(Module2, b: :desc, c: :asc)

      assert query.order_by == [{:b, :desc}, {:c, :asc}]
    end

    test "accepts a mixed list of names and direction tuples" do
      query = order_by(Module2, [:c, {:b, :desc}])

      assert query.order_by == [{:c, :asc}, {:b, :desc}]
    end

    test "appends to prior ordering" do
      query =
        Module2
        |> order_by(:c)
        |> order_by(b: :desc)

      assert query.order_by == [{:c, :asc}, {:b, :desc}]
    end

    test "composes with filtering" do
      query =
        Module2
        |> filter(a: true)
        |> order_by(:c)

      assert query.filter == [{:a, :==, true}]
      assert query.order_by == [{:c, :asc}]
    end

    test "defaults a bare attribute name to ascending" do
      assert order_by(Module2, :c) == %{
               cardinality: :set,
               entity: Module2,
               filter: [],
               include: %{},
               limit: nil,
               offset: nil,
               order_by: [{:c, :asc}]
             }
    end

    test "defaults list entries to ascending" do
      query = order_by(Module2, [:c, :a])

      assert query.order_by == [{:c, :asc}, {:a, :asc}]
    end

    test "orders by a system attribute" do
      query = order_by(Module2, :created_at)

      assert query.order_by == [{:created_at, :asc}]
    end

    test "raises on a non-atom spec" do
      expected_msg = "order_by spec must be an attribute name or a list, got: 123"

      assert_error ArgumentError, expected_msg, fn ->
        order_by(Module2, 123)
      end
    end

    test "raises on a relationship name" do
      expected_msg =
        ":c is a relationship in Hologram.Test.Fixtures.Entity.Module3 - only attributes can be ordered"

      assert_error ArgumentError, expected_msg, fn ->
        order_by(Module3, :c)
      end
    end

    test "raises on an enum attribute" do
      expected_msg =
        "ordering by enum attributes is not supported - attribute :c in Hologram.Test.Fixtures.Entity.Module4 has type :enum"

      assert_error ArgumentError, expected_msg, fn ->
        order_by(Module4, :c)
      end
    end

    test "raises on an invalid direction" do
      expected_msg = "invalid direction :down for attribute :b - use :asc or :desc"

      assert_error ArgumentError, expected_msg, fn ->
        order_by(Module2, b: :down)
      end
    end

    test "raises on an invalid entry" do
      expected_msg =
        "invalid order_by entry 123 - use an attribute name or an {attribute, :asc | :desc} tuple"

      assert_error ArgumentError, expected_msg, fn ->
        order_by(Module2, [123])
      end
    end

    test "raises on a to-one reference field" do
      expected_msg =
        "unknown attribute :c_id in Hologram.Test.Fixtures.Entity.Module3 - known attributes: :created_at, :id, :updated_at"

      assert_error ArgumentError, expected_msg, fn ->
        order_by(Module3, :c_id)
      end
    end

    test "raises on an unknown attribute" do
      expected_msg =
        "unknown attribute :x in Hologram.Test.Fixtures.Entity.Module2 - known attributes: :a, :b, :c, :created_at, :id, :updated_at"

      assert_error ArgumentError, expected_msg, fn ->
        order_by(Module2, :x)
      end
    end
  end

  describe "paginate/2" do
    test "computes a zero offset for the first page" do
      query = paginate(Module2, page: 1, size: 20)

      assert query.limit == 20
      assert query.offset == 0
    end

    test "sets the view bounds from page and size" do
      assert paginate(Module2, page: 2, size: 20) == %{
               cardinality: :set,
               entity: Module2,
               filter: [],
               include: %{},
               limit: 20,
               offset: 20,
               order_by: []
             }
    end

    test "raises on a non-integer page" do
      expected_msg = ~s(page must be a positive integer, got: "2")

      assert_error ArgumentError, expected_msg, fn ->
        paginate(Module2, page: "2", size: 20)
      end
    end

    test "raises on a non-positive page" do
      expected_msg = "page must be a positive integer, got: 0"

      assert_error ArgumentError, expected_msg, fn ->
        paginate(Module2, page: 0, size: 20)
      end
    end

    test "raises on a non-positive size" do
      expected_msg = "size must be a positive integer, got: 0"

      assert_error ArgumentError, expected_msg, fn ->
        paginate(Module2, page: 1, size: 0)
      end
    end

    test "raises on an unknown option" do
      expected_msg = "unknown paginate option :foo - supported options: :page, :size"

      assert_error ArgumentError, expected_msg, fn ->
        paginate(Module2, page: 1, size: 20, foo: 1)
      end
    end

    test "raises on non-keyword options" do
      expected_msg = "paginate options must be a keyword list, got: 5"

      assert_error ArgumentError, expected_msg, fn ->
        paginate(Module2, wrap_term(5))
      end
    end

    test "raises when the limit is already set" do
      expected_msg = "limit is already set to 10"

      assert_error ArgumentError, expected_msg, fn ->
        Module2
        |> limit(10)
        |> paginate(page: 2, size: 20)
      end
    end

    test "raises when the page option is missing" do
      expected_msg = "paginate requires the :page option"

      assert_error ArgumentError, expected_msg, fn ->
        paginate(Module2, size: 20)
      end
    end
  end
end
