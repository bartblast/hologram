defmodule Hologram.QueryTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Query

  alias Hologram.Entity
  alias Hologram.Entity.Metadata
  alias Hologram.Query.Placeholder
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module16
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

  describe "add_relationship/3" do
    test "keeps the rest of the metadata" do
      metadata = %Metadata{attribute_changes: %{c_id: "x"}, claim: :trust}
      entity = %{Entity.new(Module3) | __meta__: metadata}
      target_id = Entity.generate_id()

      result = add_relationship(entity, :a, target_id)

      assert result.__meta__.attribute_changes == %{c_id: "x"}
      assert result.__meta__.claim == :trust
      assert result.__meta__.relationship_ops == %{{:a, target_id} => :add}
    end

    test "leaves the relationship's own field as it is" do
      entity = Entity.new(Module3)

      result = add_relationship(entity, :a, Entity.generate_id())

      assert result.a == entity.a
    end

    test "records an add operation for the edge" do
      entity = Entity.new(Module3)
      target_id = Entity.generate_id()

      result = add_relationship(entity, :a, target_id)

      assert result.__meta__ == %Metadata{relationship_ops: %{{:a, target_id} => :add}}
    end

    test "records one operation per edge, several edges coexisting" do
      target_id_1 = Entity.generate_id()
      target_id_2 = Entity.generate_id()

      result =
        Module3
        |> Entity.new()
        |> add_relationship(:a, target_id_1)
        |> add_relationship(:a, target_id_2)

      assert result.__meta__.relationship_ops == %{
               {:a, target_id_1} => :add,
               {:a, target_id_2} => :add
             }
    end

    test "replaces a delete operation recorded for the same edge" do
      target_id = Entity.generate_id()

      result =
        Module3
        |> Entity.new()
        |> delete_relationship(:a, target_id)
        |> add_relationship(:a, target_id)

      assert result.__meta__.relationship_ops == %{{:a, target_id} => :add}
    end

    test "raises on a to-one relationship name" do
      entity = Entity.new(Module3)

      expected_msg =
        ":c is a to-one relationship in Hologram.Test.Fixtures.Entity.Module3 - only to-many relationships hold edges - set its reference via put_attribute(:c_id, id)"

      assert_error ArgumentError, expected_msg, fn ->
        add_relationship(entity, :c, Entity.generate_id())
      end
    end

    test "raises on an attribute name" do
      entity = Entity.new(Module16)

      expected_msg =
        ":name is an attribute in Hologram.Test.Fixtures.Entity.Module16 - only to-many relationships hold edges - put it via put_attribute"

      assert_error ArgumentError, expected_msg, fn ->
        add_relationship(entity, :name, Entity.generate_id())
      end
    end

    test "raises on an unknown relationship name" do
      entity = Entity.new(Module3)

      expected_msg =
        "unknown relationship :nope in Hologram.Test.Fixtures.Entity.Module3 - known to-many relationships: :a"

      assert_error ArgumentError, expected_msg, fn ->
        add_relationship(entity, :nope, Entity.generate_id())
      end
    end

    test "raises when the entity is not an entity struct" do
      assert_error ArgumentError, ~s(add_relationship takes an entity struct, got: "x"), fn ->
        add_relationship(wrap_term("x"), :a, Entity.generate_id())
      end
    end

    test "raises when the target id is not a string" do
      entity = Entity.new(Module3)
      expected_msg = "add_relationship takes a target id string, got: 123"

      assert_error ArgumentError, expected_msg, fn ->
        add_relationship(entity, :a, wrap_term(123))
      end
    end
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

  describe "delete_relationship/3" do
    test "keeps the rest of the metadata" do
      metadata = %Metadata{attribute_changes: %{c_id: "x"}, claim: :trust}
      entity = %{Entity.new(Module3) | __meta__: metadata}
      target_id = Entity.generate_id()

      result = delete_relationship(entity, :a, target_id)

      assert result.__meta__.attribute_changes == %{c_id: "x"}
      assert result.__meta__.claim == :trust
      assert result.__meta__.relationship_ops == %{{:a, target_id} => :delete}
    end

    test "records a delete operation for the edge" do
      entity = Entity.new(Module3)
      target_id = Entity.generate_id()

      result = delete_relationship(entity, :a, target_id)

      assert result.__meta__ == %Metadata{relationship_ops: %{{:a, target_id} => :delete}}
    end

    test "replaces an add operation recorded for the same edge" do
      target_id = Entity.generate_id()

      result =
        Module3
        |> Entity.new()
        |> add_relationship(:a, target_id)
        |> delete_relationship(:a, target_id)

      assert result.__meta__.relationship_ops == %{{:a, target_id} => :delete}
    end

    test "raises on a to-one relationship name" do
      entity = Entity.new(Module3)

      expected_msg =
        ":c is a to-one relationship in Hologram.Test.Fixtures.Entity.Module3 - only to-many relationships hold edges - set its reference via put_attribute(:c_id, id)"

      assert_error ArgumentError, expected_msg, fn ->
        delete_relationship(entity, :c, Entity.generate_id())
      end
    end

    test "raises when the entity is not an entity struct" do
      assert_error ArgumentError, ~s(delete_relationship takes an entity struct, got: "x"), fn ->
        delete_relationship(wrap_term("x"), :a, Entity.generate_id())
      end
    end

    test "raises when the target id is not a string" do
      entity = Entity.new(Module3)
      expected_msg = "delete_relationship takes a target id string, got: 123"

      assert_error ArgumentError, expected_msg, fn ->
        delete_relationship(entity, :a, wrap_term(123))
      end
    end
  end

  describe "filter/2" do
    test "accepts a placeholder sentinel as a bare equality value" do
      query = filter(Module2, b: %Placeholder{name: :bound})

      assert query.filter == [{:b, :==, {:placeholder, :bound}}]
    end

    test "accepts a placeholder sentinel as a membership list element" do
      query = filter(Module2, b: [%Placeholder{name: :bound}, 1])

      assert query.filter == [{:b, :in, [{:placeholder, :bound}, 1]}]
    end

    test "accepts a placeholder sentinel as a membership operand" do
      query = filter(Module2, b: {:in, %Placeholder{name: :ids}})

      assert query.filter == [{:b, :in, {:placeholder, :ids}}]
    end

    test "accepts a placeholder sentinel as a membership operator element" do
      query = filter(Module2, b: {:in, [%Placeholder{name: :bound}, 1]})

      assert query.filter == [{:b, :in, [{:placeholder, :bound}, 1]}]
    end

    test "accepts a placeholder sentinel as an attribute name" do
      query = filter(Module2, [{%Placeholder{name: :field}, 5}])

      assert query.filter == [{{:placeholder, :field}, :==, 5}]
    end

    test "accepts a placeholder sentinel as an attribute name with an operator" do
      query = filter(Module2, [{%Placeholder{name: :field}, {:>=, 5}}])

      assert query.filter == [{{:placeholder, :field}, :>=, 5}]
    end

    test "accepts a placeholder sentinel as an attribute name with a placeholder value" do
      query = filter(Module2, [{%Placeholder{name: :field}, %Placeholder{name: :value}}])

      assert query.filter == [{{:placeholder, :field}, :==, {:placeholder, :value}}]
    end

    test "accepts a placeholder sentinel in an inequality operator tuple" do
      query = filter(Module2, c: {:!=, %Placeholder{name: :search}})

      assert query.filter == [{:c, :!=, {:placeholder, :search}}]
    end

    test "accepts a placeholder sentinel in an ordering operator tuple" do
      query = filter(Module2, b: {:>=, %Placeholder{name: :min}})

      assert query.filter == [{:b, :>=, {:placeholder, :min}}]
    end

    test "accepts a placeholder sentinel in an ordering operator tuple on a string attribute" do
      query = filter(Module2, c: {:>=, %Placeholder{name: :min}})

      assert query.filter == [{:c, :>=, {:placeholder, :min}}]
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

    test "accepts a placeholder sentinel on a to-one reference field" do
      query = filter(Module3, c_id: %Placeholder{name: :owner})

      assert query.filter == [{:c_id, :==, {:placeholder, :owner}}]
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

    # The declared `values:` list is the order, so a comparison reads it - `{:>, :x}` means every
    # value declared after :x.
    test "builds an ordering triple for an enum attribute" do
      query = filter(Module4, c: {:>, :x})

      assert query.filter == [{:c, :>, :x}]
    end

    test "builds an ordering triple for an integer attribute" do
      query = filter(Module2, b: {:>=, 3})

      assert query.filter == [{:b, :>=, 3}]
    end

    # The derived sort key is the order, so a comparison reads it the way `order_by` does - a
    # bound names a position in the list the attribute sorts into.
    test "builds an ordering triple for a string attribute" do
      query = filter(Module2, c: {:>=, "x"})

      assert query.filter == [{:c, :>=, "x"}]
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

    test "raises on a comparison against a value the enum does not declare" do
      expected_msg =
        ":z is not a value of attribute :c in Hologram.Test.Fixtures.Entity.Module4 - the values are [:x, :y]"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module4, c: {:>, :z})
      end
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
        "operator :>= requires an orderable attribute - attribute :c_id in Hologram.Test.Fixtures.Entity.Module3 has type :uuid, and boolean and uuid attributes have no order to compare by"

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

    test "raises on an ordering comparison on the id attribute" do
      expected_msg =
        "operator :< requires an orderable attribute - attribute :id in Hologram.Test.Fixtures.Entity.Module2 has type :uuid, and boolean and uuid attributes have no order to compare by"

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

    test "raises on an unknown operator with a placeholder operand" do
      expected_msg =
        "unknown operator :like in the filter predicate for attribute :b - supported operators: :!=, :<, :<=, :==, :>, :>=, :in, :not_in"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, b: {:like, %Placeholder{name: :x}})
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
    test "accepts a placeholder" do
      query = limit(Module2, %Placeholder{name: :size})

      assert query.limit == {:placeholder, :size}
    end

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

    test "replaces a prior limit" do
      query =
        Module2
        |> limit(50)
        |> limit(100)

      assert query.limit == 100
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
  end

  describe "normalize/1" do
    test "appends an ascending id tiebreaker after a placeholder ordering key" do
      query =
        Module2
        |> order_by(%Placeholder{name: :sort})
        |> normalize()

      assert query.order_by == [{{:placeholder, :sort}, :asc}, {:id, :asc}]
    end

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
    test "accepts a placeholder" do
      query = offset(Module2, %Placeholder{name: :start})

      assert query.offset == {:placeholder, :start}
    end

    test "replaces a prior offset" do
      query =
        Module2
        |> offset(20)
        |> offset(40)

      assert query.offset == 40
    end

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

    test "accepts a placeholder as a bare spec" do
      query = order_by(Module2, %Placeholder{name: :sort})

      assert query.order_by == [{{:placeholder, :sort}, :asc}]
    end

    test "accepts a placeholder as a direction" do
      query = order_by(Module2, c: %Placeholder{name: :dir})

      assert query.order_by == [{:c, {:placeholder, :dir}}]
    end

    test "accepts a placeholder as an ordering key" do
      query = order_by(Module2, [{%Placeholder{name: :sort}, :desc}])

      assert query.order_by == [{{:placeholder, :sort}, :desc}]
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

    # The declared `values:` list is the order, so nothing about an enum keeps it from being an
    # ordering key - both executors sort by a value's position in that list.
    test "orders by an enum attribute" do
      query = order_by(Module4, :c)

      assert query.order_by == [{:c, :asc}]
    end

    test "replaces prior ordering" do
      query =
        Module2
        |> order_by(:c)
        |> order_by(b: :desc)

      assert query.order_by == [{:b, :desc}]
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
    test "accepts a placeholder page" do
      query = paginate(Module2, page: %Placeholder{name: :page}, size: 20)

      assert query.offset == {:placeholder, :page}
      assert query.limit == 20
    end

    test "accepts a placeholder size" do
      query = paginate(Module2, page: 3, size: %Placeholder{name: :size})

      assert query.offset == {:placeholder, :size}
      assert query.limit == {:placeholder, :size}
    end

    test "computes a zero offset for the first page" do
      query = paginate(Module2, page: 1, size: 20)

      assert query.limit == 20
      assert query.offset == 0
    end

    test "replaces prior view bounds" do
      query =
        Module2
        |> limit(10)
        |> paginate(page: 2, size: 20)

      assert query.limit == 20
      assert query.offset == 20
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

    test "raises when the page option is missing" do
      expected_msg = "paginate requires the :page option"

      assert_error ArgumentError, expected_msg, fn ->
        paginate(Module2, size: 20)
      end
    end
  end

  describe "placeholder_names/1" do
    test "collects placeholders from every position of a term" do
      query =
        Module2
        |> filter(b: {:>=, %Placeholder{name: :min_b}})
        |> filter([{%Placeholder{name: :field}, 5}])
        |> limit(%Placeholder{name: :size})
        |> offset(%Placeholder{name: :start})
        |> order_by([{%Placeholder{name: :sort}, %Placeholder{name: :dir}}])

      assert placeholder_names(query) == [:min_b, :field, :size, :start, :sort, :dir]
    end

    test "collects placeholders from include sub-terms" do
      query = include(Module3, :a, &filter(&1, c: %Placeholder{name: :owner}))

      assert placeholder_names(query) == [:owner]
    end

    test "yields an empty list for a concrete term" do
      assert placeholder_names(filter(Module2, a: true)) == []
    end
  end

  describe "put_attribute/2" do
    test "accepts a map of values" do
      entity = Entity.new(Module2, c: "x")

      result = put_attribute(entity, %{b: 7})

      assert result.b == 7
      assert result.__meta__ == %Metadata{attribute_changes: %{b: 7}}
    end

    test "keeps the rest of the metadata" do
      metadata = %Metadata{claim: :trust, relationship_ops: %{{:a, "x"} => :add}}
      entity = %{Entity.new(Module3) | __meta__: metadata}

      result = put_attribute(entity, b_id: Entity.generate_id())

      assert result.__meta__.claim == :trust
      assert result.__meta__.relationship_ops == %{{:a, "x"} => :add}
    end

    test "merges into the changes already recorded, the later value replacing the earlier" do
      result =
        Module2
        |> Entity.new(c: "x")
        |> put_attribute(a: true, c: "y")
        |> put_attribute(c: "z")

      assert result.c == "z"
      assert result.__meta__ == %Metadata{attribute_changes: %{a: true, c: "z"}}
    end

    test "sets a to-one reference field" do
      target_id = Entity.generate_id()
      entity = Entity.new(Module3)

      result = put_attribute(entity, b_id: target_id)

      assert result.b_id == target_id
      assert result.__meta__ == %Metadata{attribute_changes: %{b_id: target_id}}
    end

    test "sets the values on the struct and records them as changes" do
      entity = Entity.new(Module2, c: "x")

      result = put_attribute(entity, a: true, c: "y")

      assert result.a == true
      assert result.c == "y"
      assert result.__meta__ == %Metadata{attribute_changes: %{a: true, c: "y"}}
    end

    test "raises on a system attribute name" do
      entity = Entity.new(Module2, c: "x")

      expected_msg =
        ":id is a system attribute of Hologram.Test.Fixtures.Entity.Module2 - it is managed automatically and can't be put"

      assert_error ArgumentError, expected_msg, fn ->
        put_attribute(entity, id: Entity.generate_id())
      end
    end

    test "raises on a to-many relationship name" do
      entity = Entity.new(Module3)

      expected_msg =
        ":a is a relationship in Hologram.Test.Fixtures.Entity.Module3 - only attributes can be put - add its edges via add_relationship"

      assert_error ArgumentError, expected_msg, fn ->
        put_attribute(entity, a: [])
      end
    end

    test "raises on a to-one relationship name" do
      entity = Entity.new(Module3)

      expected_msg =
        ":c is a relationship in Hologram.Test.Fixtures.Entity.Module3 - only attributes can be put - set its reference via :c_id"

      assert_error ArgumentError, expected_msg, fn ->
        put_attribute(entity, c: Entity.new(Module1))
      end
    end

    test "raises on an unknown name" do
      entity = Entity.new(Module3)

      expected_msg =
        "unknown attribute :nope in Hologram.Test.Fixtures.Entity.Module3 - known attributes: :b_id, :c_id"

      assert_error ArgumentError, expected_msg, fn ->
        put_attribute(entity, nope: 1)
      end
    end

    test "raises when the entity is not an entity struct" do
      assert_error ArgumentError, ~s(put_attribute takes an entity struct, got: "x"), fn ->
        put_attribute(wrap_term("x"), a: true)
      end

      assert_error ArgumentError,
                   "put_attribute takes an entity struct, got: Hologram.Test.Fixtures.Entity.Module2",
                   fn -> put_attribute(wrap_term(Module2), a: true) end
    end

    test "raises when the values are neither a keyword list nor a map" do
      entity = Entity.new(Module2, c: "x")

      assert_error ArgumentError,
                   "put_attribute takes a keyword list or a map of attribute values, got: [1, 2]",
                   fn -> put_attribute(entity, [1, 2]) end

      assert_error ArgumentError,
                   ~s(put_attribute takes a keyword list or a map of attribute values, got: "a"),
                   fn -> put_attribute(entity, wrap_term("a")) end
    end
  end

  describe "put_attribute/3" do
    test "sets the value on the struct and records it as a change" do
      entity = Entity.new(Module2, c: "x")

      result = put_attribute(entity, :a, true)

      assert result.a == true
      assert result.__meta__ == %Metadata{attribute_changes: %{a: true}}
    end

    test "raises on an unknown name" do
      entity = Entity.new(Module2, c: "x")

      expected_msg =
        "unknown attribute :nope in Hologram.Test.Fixtures.Entity.Module2 - known attributes: :a, :b, :c"

      assert_error ArgumentError, expected_msg, fn ->
        put_attribute(entity, :nope, 1)
      end
    end
  end
end
