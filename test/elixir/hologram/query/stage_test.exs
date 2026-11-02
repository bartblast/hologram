defmodule Hologram.Query.StageTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Query.Stage

  alias Hologram.Entity
  alias Hologram.Entity.Metadata
  alias Hologram.Query
  alias Hologram.Query.Placeholder
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module10
  alias Hologram.Test.Fixtures.Entity.Module16
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module22
  alias Hologram.Test.Fixtures.Entity.Module24
  alias Hologram.Test.Fixtures.Entity.Module25
  alias Hologram.Test.Fixtures.Entity.Module26
  alias Hologram.Test.Fixtures.Entity.Module27
  alias Hologram.Test.Fixtures.Entity.Module28
  alias Hologram.Test.Fixtures.Entity.Module29
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module31
  alias Hologram.Test.Fixtures.Entity.Module4
  alias Hologram.Test.Fixtures.Entity.Module5
  alias Hologram.Test.Fixtures.Policy

  defp base_term(entity_type) do
    %Query{entity: entity_type}
  end

  describe "add_relationship/3" do
    test "keeps the rest of the metadata" do
      metadata = %Metadata{attribute_ops: %{c_id: {:put, "x"}}, claim: :trust}
      entity = %{Module3.new() | __meta__: metadata}
      target_id = Entity.generate_id()

      result = add_relationship(entity, :a, target_id)

      assert result.__meta__.attribute_ops == %{c_id: {:put, "x"}}
      assert result.__meta__.claim == :trust
      assert result.__meta__.relationship_ops == %{{:a, target_id} => :add}
    end

    test "leaves the relationship's own field as it is" do
      entity = Module3.new()

      result = add_relationship(entity, :a, Entity.generate_id())

      assert result.a == entity.a
    end

    test "records an add operation for the edge" do
      entity = Module3.new()
      target_id = Entity.generate_id()

      result = add_relationship(entity, :a, target_id)

      assert result.__meta__ == %Metadata{relationship_ops: %{{:a, target_id} => :add}}
    end

    test "records one operation per edge, several edges coexisting" do
      target_id_1 = Entity.generate_id()
      target_id_2 = Entity.generate_id()
      entity = Module3.new()

      result =
        entity
        |> add_relationship(:a, target_id_1)
        |> add_relationship(:a, target_id_2)

      assert result.__meta__.relationship_ops == %{
               {:a, target_id_1} => :add,
               {:a, target_id_2} => :add
             }
    end

    test "replaces a delete operation recorded for the same edge" do
      target_id = Entity.generate_id()
      entity = Module3.new()

      result =
        entity
        |> delete_relationship(:a, target_id)
        |> add_relationship(:a, target_id)

      assert result.__meta__.relationship_ops == %{{:a, target_id} => :add}
    end

    test "raises on an inverse of a to-one" do
      entity = Module26.new()

      expected_msg =
        ":messages is an inverse relationship in Hologram.Test.Fixtures.Entity.Module26 - it reads the channel_id reference of Hologram.Test.Fixtures.Entity.Module28, so set that reference on the Hologram.Test.Fixtures.Entity.Module28 row via put_attribute(:channel_id, id)"

      assert_error ArgumentError, expected_msg, fn ->
        add_relationship(entity, :messages, Entity.generate_id())
      end
    end

    test "raises on a single inverse" do
      entity = Module26.new()

      expected_msg =
        ":topic is an inverse relationship in Hologram.Test.Fixtures.Entity.Module26 - it reads the channel_id reference of Hologram.Test.Fixtures.Entity.Module27, so set that reference on the Hologram.Test.Fixtures.Entity.Module27 row via put_attribute(:channel_id, id)"

      assert_error ArgumentError, expected_msg, fn ->
        add_relationship(entity, :topic, Entity.generate_id())
      end
    end

    test "raises on an inverse of a to-many" do
      entity = Module29.new()

      expected_msg =
        ":messages is an inverse relationship in Hologram.Test.Fixtures.Entity.Module29 - it reads the labels relationship of Hologram.Test.Fixtures.Entity.Module28, so record the edge on the Hologram.Test.Fixtures.Entity.Module28 row via add_relationship(:labels, id)"

      assert_error ArgumentError, expected_msg, fn ->
        add_relationship(entity, :messages, Entity.generate_id())
      end
    end

    test "raises on a to-one relationship name" do
      entity = Module3.new()

      expected_msg =
        ":c is a to-one relationship in Hologram.Test.Fixtures.Entity.Module3 - only to-many relationships hold edges - set its reference via put_attribute(:c_id, id)"

      assert_error ArgumentError, expected_msg, fn ->
        add_relationship(entity, :c, Entity.generate_id())
      end
    end

    test "raises on an attribute name" do
      entity = Module16.new()

      expected_msg =
        ":name is an attribute in Hologram.Test.Fixtures.Entity.Module16 - only to-many relationships hold edges - put it via put_attribute"

      assert_error ArgumentError, expected_msg, fn ->
        add_relationship(entity, :name, Entity.generate_id())
      end
    end

    test "raises on an unknown relationship name" do
      entity = Module3.new()

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
      entity = Module3.new()
      expected_msg = "add_relationship takes a target id string, got: 123"

      assert_error ArgumentError, expected_msg, fn ->
        add_relationship(entity, :a, wrap_term(123))
      end
    end
  end

  describe "authorize/2" do
    test "keeps the rest of the metadata" do
      target_id = Entity.generate_id()
      entity = Module3.new()

      result =
        entity
        |> put_attribute(c_id: target_id)
        |> add_relationship(:a, target_id)
        |> authorize(:update)

      assert result.__meta__.attribute_ops == %{c_id: {:put, target_id}}
      assert result.__meta__.relationship_ops == %{{:a, target_id} => :add}
      assert result.__meta__.claim == {:authorize, :update}
    end

    test "records the claim for the operation" do
      entity = Module2.new(c: "x")

      result = authorize(entity, :update)

      assert result.__meta__ == %Metadata{claim: {:authorize, :update}}
    end

    test "records an operation an allow line on the entity type names" do
      result = authorize(Policy.Module1.new(), :archive)

      assert result.__meta__.claim == {:authorize, :archive}
    end

    test "raises when the entity is not an entity struct" do
      assert_error ArgumentError, ~s(authorize takes an entity struct, got: "x"), fn ->
        authorize(wrap_term("x"), :archive)
      end
    end

    test "raises when the operation is not an atom" do
      entity = Module2.new(c: "x")
      expected_msg = ~s(authorize takes an operation atom, got: "archive")

      assert_error ArgumentError, expected_msg, fn ->
        authorize(entity, wrap_term("archive"))
      end
    end

    test "raises when the struct already carries an authorize claim" do
      entity = Module2.new(c: "x")

      expected_msg =
        "Hologram.Test.Fixtures.Entity.Module2 already carries a claim ({:authorize, :update}) - a write claims exactly one authority"

      assert_error ArgumentError, expected_msg, fn ->
        entity
        |> authorize(:update)
        |> authorize(:delete)
      end
    end

    test "raises when the struct already carries a trust claim" do
      entity = Module2.new(c: "x")

      expected_msg =
        "Hologram.Test.Fixtures.Entity.Module2 already carries a claim (:trust) - a write claims exactly one authority"

      assert_error ArgumentError, expected_msg, fn ->
        entity
        |> trust()
        |> authorize(:update)
      end
    end

    test "raises when the operation is one the entity type never declared" do
      expected_msg =
        "unknown operation :archive for Hologram.Test.Fixtures.Entity.Module2 - its allow lines declare no operation of their own, and the framework's own operations are :create, :delete, :grant_role, :read, :read_roles, :revoke_role and :update"

      assert_error ArgumentError, expected_msg, fn ->
        authorize(Module2.new(c: "x"), :archive)
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
      assert count(Module2) == %Query{cardinality: :count, entity: Module2}
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

  describe "decrement/3" do
    test "records a positive amount as a negative delta" do
      entity = Module10.new(count: 5)

      result = decrement(entity, :count, 2)

      assert result.__meta__ == %Metadata{attribute_ops: %{count: {:increment, -2}}}
    end

    test "subtracts from a recorded increment" do
      result =
        %{count: 5}
        |> Module10.new()
        |> increment(:count, 5)
        |> decrement(:count, 2)

      assert result.__meta__ == %Metadata{attribute_ops: %{count: {:increment, 3}}}
    end

    test "drops a delta that nets to zero" do
      result =
        %{count: 5}
        |> Module10.new()
        |> increment(:count, 2)
        |> decrement(:count, 2)

      assert result.__meta__ == %Metadata{}
    end

    test "raises on an amount that is not a positive integer" do
      entity = Module10.new(count: 5)

      assert_error ArgumentError, "decrement takes a positive integer amount, got: -1", fn ->
        decrement(entity, :count, -1)
      end

      assert_error ArgumentError, "decrement takes a positive integer amount, got: 0", fn ->
        decrement(entity, :count, 0)
      end

      assert_error ArgumentError, "decrement takes a positive integer amount, got: 1.5", fn ->
        decrement(entity, :count, 1.5)
      end
    end

    test "raises on a non-integer attribute" do
      entity = Module10.new(count: 5)

      expected_msg =
        ":bio is a :string attribute of Hologram.Test.Fixtures.Entity.Module10 - decrement moves integer attributes only"

      assert_error ArgumentError, expected_msg, fn ->
        decrement(entity, :bio, 1)
      end
    end
  end

  describe "delete_relationship/3" do
    test "keeps the rest of the metadata" do
      metadata = %Metadata{attribute_ops: %{c_id: {:put, "x"}}, claim: :trust}
      entity = %{Module3.new() | __meta__: metadata}
      target_id = Entity.generate_id()

      result = delete_relationship(entity, :a, target_id)

      assert result.__meta__.attribute_ops == %{c_id: {:put, "x"}}
      assert result.__meta__.claim == :trust
      assert result.__meta__.relationship_ops == %{{:a, target_id} => :delete}
    end

    test "records a delete operation for the edge" do
      entity = Module3.new()
      target_id = Entity.generate_id()

      result = delete_relationship(entity, :a, target_id)

      assert result.__meta__ == %Metadata{relationship_ops: %{{:a, target_id} => :delete}}
    end

    test "replaces an add operation recorded for the same edge" do
      target_id = Entity.generate_id()
      entity = Module3.new()

      result =
        entity
        |> add_relationship(:a, target_id)
        |> delete_relationship(:a, target_id)

      assert result.__meta__.relationship_ops == %{{:a, target_id} => :delete}
    end

    test "raises on an inverse of a to-many in its own stage's words" do
      entity = Module29.new()

      expected_msg =
        ":messages is an inverse relationship in Hologram.Test.Fixtures.Entity.Module29 - it reads the labels relationship of Hologram.Test.Fixtures.Entity.Module28, so record the edge on the Hologram.Test.Fixtures.Entity.Module28 row via delete_relationship(:labels, id)"

      assert_error ArgumentError, expected_msg, fn ->
        delete_relationship(entity, :messages, Entity.generate_id())
      end
    end

    test "raises on a to-one relationship name" do
      entity = Module3.new()

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
      entity = Module3.new()
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

    # The attribute is unknown, so nothing can say whether the other one compares with it - the
    # triple records what was written, as for any placeholder-keyed predicate.
    test "accepts a placeholder sentinel as an attribute name with a bare attribute operand" do
      query = filter(Module2, [{%Placeholder{name: :field}, {:attribute, :b}}])

      assert query.filter == [{{:placeholder, :field}, :==, {:attribute, :b}}]
    end

    test "accepts a placeholder sentinel as an attribute name with an attribute operand" do
      query = filter(Module2, [{%Placeholder{name: :field}, {:<, {:attribute, :b}}}])

      assert query.filter == [{{:placeholder, :field}, :<, {:attribute, :b}}]
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

    test "accepts a placeholder sentinel inside an alternative" do
      query = filter(Module2, or: [[b: %Placeholder{name: :min}], [a: true]])

      assert query.filter == [{:or, [[{:b, :==, {:placeholder, :min}}], [{:a, :==, true}]]}]
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

    test "appends a disjunction after prior predicates" do
      query =
        Module2
        |> filter(a: true)
        |> filter(or: [[b: 1], [c: "x"]])

      assert query.filter == [{:a, :==, true}, {:or, [[{:b, :==, 1}], [{:c, :==, "x"}]]}]
    end

    test "appends to an already built query term" do
      query =
        Module2
        |> filter(a: true)
        |> filter(b: 123)

      assert query == %Query{entity: Module2, filter: [{:a, :==, true}, {:b, :==, 123}]}
    end

    test "builds a membership triple for a path" do
      query = filter(Module3, [{[:b, :c], {:in, ["x", "y"]}}])

      assert query.filter == [{[:b, :c], :in, ["x", "y"]}]
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

    test "builds a triple for a one-hop path" do
      query = filter(Module3, [{[:b, :a], true}])

      assert query.filter == [{[:b, :a], :==, true}]
    end

    test "builds a triple for a two-hop path" do
      query = filter(Module5, [{[:a, :b, :c], "x"}])

      assert query.filter == [{[:a, :b, :c], :==, "x"}]
    end

    test "builds an actor triple under an equality operator" do
      query = filter(Module3, c_id: {:!=, {:actor}})

      assert query.filter == [{:c_id, :!=, {:actor}}]
    end

    test "builds an actor triple for a path to a uuid attribute" do
      query = filter(Module3, [{[:b, :id], {:actor}}])

      assert query.filter == [{[:b, :id], :==, {:actor}}]
    end

    test "builds an attribute equality triple from a bare attribute operand" do
      query = filter(Module10, count: {:attribute, :priority})

      assert query.filter == [{:count, :==, {:attribute, :priority}}]
    end

    test "builds an attribute triple between two paths" do
      query = filter(Module25, [{[:e, :ends_on], {:<, {:attribute, [:e, :starts_on]}}}])

      assert query.filter == [{[:e, :ends_on], :<, {:attribute, [:e, :starts_on]}}]
    end

    test "builds an attribute triple for a date pair" do
      query = filter(Module24, ends_on: {:<, {:attribute, :starts_on}})

      assert query.filter == [{:ends_on, :<, {:attribute, :starts_on}}]
    end

    test "builds an attribute triple for a float compared with an integer" do
      query = filter(Module10, rating: {:>, {:attribute, :count}})

      assert query.filter == [{:rating, :>, {:attribute, :count}}]
    end

    test "builds an attribute triple for a string pair" do
      query = filter(Module10, username: {:<, {:attribute, :bio}})

      assert query.filter == [{:username, :<, {:attribute, :bio}}]
    end

    test "builds an attribute triple for a system attribute operand" do
      query = filter(Module2, updated_at: {:>, {:attribute, :created_at}})

      assert query.filter == [{:updated_at, :>, {:attribute, :created_at}}]
    end

    test "builds an attribute triple for an enum pair" do
      query = filter(Module24, level: {:<, {:attribute, :priority}})

      assert query.filter == [{:level, :<, {:attribute, :priority}}]
    end

    test "builds an attribute triple for a path operand" do
      query = filter(Module3, c_id: {:attribute, [:b, :id]})

      assert query.filter == [{:c_id, :==, {:attribute, [:b, :id]}}]
    end

    test "builds an attribute triple for an integer compared with a float" do
      query = filter(Module10, count: {:<, {:attribute, :rating}})

      assert query.filter == [{:count, :<, {:attribute, :rating}}]
    end

    test "builds an attribute triple for two reference fields" do
      query = filter(Module5, a_id: {:==, {:attribute, :b_id}})

      assert query.filter == [{:a_id, :==, {:attribute, :b_id}}]
    end

    test "builds an attribute triple under each comparison operator" do
      for operator <- [:!=, :<, :<=, :==, :>, :>=] do
        query = filter(Module10, count: {operator, {:attribute, :priority}})

        assert query.filter == [{:count, operator, {:attribute, :priority}}]
      end
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

    test "builds an ordering triple for a path to an enum attribute" do
      query = filter(Module25, [{[:e, :priority], {:>=, :medium}}])

      assert query.filter == [{[:e, :priority], :>=, :medium}]
    end

    test "builds an ordering triple for a path to an integer attribute" do
      query = filter(Module3, [{[:b, :b], {:>=, 3}}])

      assert query.filter == [{[:b, :b], :>=, 3}]
    end

    test "builds an ordering triple for an integer attribute" do
      query = filter(Module2, b: {:>=, 3})

      assert query.filter == [{:b, :>=, 3}]
    end

    # The derived sort key is the order, so a comparison reads it the way `sort` does - a
    # bound names a position in the list the attribute sorts into.
    test "builds an ordering triple for a string attribute" do
      query = filter(Module2, c: {:>=, "x"})

      assert query.filter == [{:c, :>=, "x"}]
    end

    test "builds an ordering triple for a time attribute" do
      query = filter(Module22, opens_at: {:>, ~T[11:00:00]})

      assert query.filter == [{:opens_at, :>, ~T[11:00:00]}]
    end

    test "builds conjunction triples from a list of operator tuples" do
      query = filter(Module2, b: [{:>=, 3}, {:<, 10}])

      assert query.filter == [{:b, :>=, 3}, {:b, :<, 10}]
    end

    test "expands a range inside an alternative into its two bounds" do
      query = filter(Module2, or: [[b: 1..3], [a: true]])

      assert query.filter == [{:or, [[{:b, :>=, 1}, {:b, :<=, 3}], [{:a, :==, true}]]}]
    end

    test "expands a range on a path into its two bounds" do
      query = filter(Module3, [{[:b, :b], 1..3}])

      assert query.filter == [{[:b, :b], :>=, 1}, {[:b, :b], :<=, 3}]
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

    test "nests a disjunction inside an alternative" do
      query = filter(Module2, or: [[a: true, or: [[b: 1], [b: 2]]], [c: "x"]])

      assert query.filter == [
               {:or,
                [
                  [{:a, :==, true}, {:or, [[{:b, :==, 1}], [{:b, :==, 2}]]}],
                  [{:c, :==, "x"}]
                ]}
             ]
    end

    test "reads an or entry as a disjunction of its alternatives" do
      query = filter(Module2, or: [[a: true], [b: {:>=, 3}, c: "x"]])

      assert query.filter == [{:or, [[{:a, :==, true}], [{:b, :>=, 3}, {:c, :==, "x"}]]}]
    end

    test "starts a query term from an entity type module" do
      assert filter(Module2, a: true) == %Query{entity: Module2, filter: [{:a, :==, true}]}
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

    test "raises on a comparison against a value the enum a path ends at does not declare" do
      expected_msg =
        ":urgent is not a value of attribute e.priority in Hologram.Test.Fixtures.Entity.Module25 - the values are [:low, :medium, :high]"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module25, [{[:e, :priority], {:>=, :urgent}}])
      end
    end

    test "raises on a descending range" do
      expected_msg =
        "stepped range 10..3//-1 for attribute :b is not supported - membership ranges use step 1"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, b: 10..3//-1)
      end
    end

    test "raises on a disjunction with no alternatives" do
      expected_msg = "a disjunction takes a list of at least two predicate lists, got: []"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, or: [])
      end
    end

    test "raises on a disjunction with one alternative" do
      expected_msg =
        "a disjunction takes a list of at least two predicate lists, got: [[a: true]]"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, or: [[a: true]])
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

    test "raises on a map shaped like a query term" do
      term = Map.from_struct(%Query{entity: Module2})

      expected_msg =
        ~s(#{inspect(term)} is not an entity type module or a query term - a query starts from a module with the "use Hologram.Entity" directive)

      assert_error ArgumentError, expected_msg, fn ->
        filter(term, a: true)
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

    test "raises on a one-element list as a predicate name" do
      expected_msg =
        "filter predicates must be a list of name and value pairs - a name being an attribute or a path - got: [{[:a], true}]"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, [{[:a], true}])
      end
    end

    test "raises on a one-element list as an attribute operand" do
      expected_msg =
        "invalid attribute operand {:attribute, [:b]} - an attribute is named by an atom, and a path by a list of two or more atoms"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, c: {:attribute, [:b]})
      end
    end

    test "raises on a path and an attribute of different types" do
      expected_msg =
        "operator :== compares attribute :c_id with attribute b.c in Hologram.Test.Fixtures.Entity.Module3, which have different types (:uuid and :string) - two attributes compare when they have the same type, or when one widens to the other (:integer to :float)"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module3, c_id: {:attribute, [:b, :c]})
      end
    end

    test "raises on a path compared with itself" do
      expected_msg =
        "operator :< compares attribute b.b in Hologram.Test.Fixtures.Entity.Module3 with itself"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module3, [{[:b, :b], {:<, {:attribute, [:b, :b]}}}])
      end
    end

    test "raises on a path through an inverse relationship" do
      expected_msg =
        ":messages is an inverse relationship in Hologram.Test.Fixtures.Entity.Module26 - a path in a condition goes through to-one relationships that hold their reference"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module26, [{[:messages, :body], "x"}])
      end
    end

    test "raises on a path reaching an inverse relationship on a later hop" do
      expected_msg =
        ":messages is an inverse relationship in Hologram.Test.Fixtures.Entity.Module26 - a path in a condition goes through to-one relationships that hold their reference"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module28, [{[:channel, :messages, :body], "x"}])
      end
    end

    test "raises on an attribute operand reading a path through an inverse relationship" do
      expected_msg =
        ":messages is an inverse relationship in Hologram.Test.Fixtures.Entity.Module26 - a path in a condition goes through to-one relationships that hold their reference"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module26, [{:name, {:==, {:attribute, [:messages, :body]}}}])
      end
    end

    test "raises on a path through a single inverse" do
      expected_msg =
        ":topic is an inverse relationship in Hologram.Test.Fixtures.Entity.Module26 - a path in a condition goes through to-one relationships that hold their reference"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module26, [{[:topic, :summary], "x"}])
      end
    end

    test "raises on a path through a to-many relationship" do
      expected_msg =
        ":a is a to-many relationship in Hologram.Test.Fixtures.Entity.Module3 - a path in a condition goes through to-one relationships only"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module3, [{[:a, :c], "x"}])
      end
    end

    test "raises on a path through an attribute" do
      expected_msg =
        ":c is an attribute in Hologram.Test.Fixtures.Entity.Module2 - a path goes through relationships, and only its last name is an attribute"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, [{[:c, :x], 1}])
      end
    end

    test "raises on a path through an unknown relationship" do
      expected_msg =
        "unknown relationship :x in Hologram.Test.Fixtures.Entity.Module3 - known relationships: :a, :b, :c"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module3, [{[:x, :a], true}])
      end
    end

    test "raises on a path through an unknown relationship on a later hop" do
      expected_msg =
        "unknown relationship :x in Hologram.Test.Fixtures.Entity.Module3 - known relationships: :a, :b, :c"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module5, [{[:a, :x, :c], "x"}])
      end
    end

    test "raises on a path to a relationship" do
      expected_msg =
        ":b is a relationship in Hologram.Test.Fixtures.Entity.Module3 - only attributes can be filtered - filter its reference via :b_id"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module5, [{[:a, :b], nil}])
      end
    end

    test "raises on a path to an unknown attribute" do
      expected_msg =
        "unknown attribute :x in Hologram.Test.Fixtures.Entity.Module2 - known attributes: :a, :b, :c, :created_at, :id, :updated_at"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module3, [{[:b, :x], 1}])
      end
    end

    test "raises on a predicate naming a to-one relationship" do
      expected_msg =
        ":c is a relationship in Hologram.Test.Fixtures.Entity.Module3 - only attributes can be filtered - filter its reference via :c_id"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module3, c: "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f")
      end
    end

    test "raises on a predicate naming an inverse relationship" do
      expected_msg =
        ":messages is a relationship in Hologram.Test.Fixtures.Entity.Module26 - only attributes can be filtered"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module26, messages: "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f")
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

    test "raises on a relationship as an attribute operand" do
      expected_msg =
        ":c is a relationship in Hologram.Test.Fixtures.Entity.Module3 - only attributes can be filtered - filter its reference via :c_id"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module3, b_id: {:==, {:attribute, :c}})
      end
    end

    test "raises on a stepped range" do
      expected_msg =
        "stepped range 3..10//2 for attribute :b is not supported - membership ranges use step 1"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, b: 3..10//2)
      end
    end

    test "raises on an alternative that is not a list of name and value pairs" do
      expected_msg =
        "an alternative of a disjunction is a non-empty list of name and value pairs, got: [1]"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, or: [[a: true], [1]])
      end
    end

    test "raises on an attribute compared with itself" do
      expected_msg =
        "operator :< compares attribute :count in Hologram.Test.Fixtures.Entity.Module10 with itself"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module10, count: {:<, {:attribute, :count}})
      end
    end

    test "raises on an attribute operand for a membership operator" do
      expected_msg =
        "operator :in on attribute :count requires a list operand, got: {:attribute, :priority}"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module10, count: {:in, {:attribute, :priority}})
      end
    end

    test "raises on an attribute pair of different types" do
      expected_msg =
        "operator :< compares attribute :released_on with attribute :held_at in Hologram.Test.Fixtures.Entity.Module10, which have different types (:date and :datetime) - two attributes compare when they have the same type, or when one widens to the other (:integer to :float)"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module10, released_on: {:<, {:attribute, :held_at}})
      end
    end

    test "raises on an empty alternative" do
      expected_msg =
        "an alternative of a disjunction is a non-empty list of name and value pairs, got: []"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, or: [[a: true], []])
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

    test "raises on an enum pair declaring different values" do
      expected_msg =
        "operator :== compares attribute :level with attribute :tier in Hologram.Test.Fixtures.Entity.Module24, which declare different values ([:low, :medium, :high] and [:low, :high]) - two enum attributes compare only when they declare the same values in the same order"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module24, level: {:==, {:attribute, :tier}})
      end
    end

    test "raises on an invalid tuple filter value" do
      expected_msg = "invalid filter value {1, 2, 3} for attribute :b"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, b: {1, 2, 3})
      end
    end

    # The shape decides, not the name, so an or entry holding anything but predicate lists is read
    # as an attribute named or - which this entity type does not declare.
    test "raises on an or entry whose value is not a list of lists as an unknown attribute" do
      expected_msg =
        "unknown attribute :or in Hologram.Test.Fixtures.Entity.Module2 - known attributes: :a, :b, :c, :created_at, :id, :updated_at"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, or: true)
      end
    end

    test "raises on an ordering comparison between reference fields" do
      expected_msg =
        "operator :< requires an orderable attribute - attribute :a_id in Hologram.Test.Fixtures.Entity.Module5 has type :uuid, and boolean and uuid attributes have no order to compare by"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module5, a_id: {:<, {:attribute, :b_id}})
      end
    end

    test "raises on an ordering comparison on a path to a boolean attribute" do
      expected_msg =
        "operator :> requires an orderable attribute - attribute b.a in Hologram.Test.Fixtures.Entity.Module3 has type :boolean, and boolean and uuid attributes have no order to compare by"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module3, [{[:b, :a], {:>, true}}])
      end
    end

    test "raises on an ordering comparison on the id attribute" do
      expected_msg =
        "operator :< requires an orderable attribute - attribute :id in Hologram.Test.Fixtures.Entity.Module2 has type :uuid, and boolean and uuid attributes have no order to compare by"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, id: {:<, "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f"})
      end
    end

    test "raises on an unknown attribute inside an alternative" do
      expected_msg =
        "unknown attribute :x in Hologram.Test.Fixtures.Entity.Module2 - known attributes: :a, :b, :c, :created_at, :id, :updated_at"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, or: [[x: 1], [a: true]])
      end
    end

    test "raises on an unknown attribute operand" do
      expected_msg =
        "unknown attribute :x in Hologram.Test.Fixtures.Entity.Module2 - known attributes: :a, :b, :c, :created_at, :id, :updated_at"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, b: {:==, {:attribute, :x}})
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

    test "raises on predicates that are not a list of name and value pairs" do
      expected_msg =
        "filter predicates must be a list of name and value pairs - a name being an attribute or a path - got: [:a]"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, [:a])
      end
    end
  end

  describe "filter/2 - quantifiers" do
    test "quantifies over an inverse of a to-one" do
      query = filter(Module26, any: {[:messages], [body: "hi"]})

      assert query.filter == [{:any, {[:messages], [{:body, :==, "hi"}]}}]
    end

    test "quantifies over a stored to-many" do
      query = filter(Module28, any: {[:labels], [name: "urgent"]})

      assert query.filter == [{:any, {[:labels], [{:name, :==, "urgent"}]}}]
    end

    test "quantifies over an inverse of a to-many" do
      query = filter(Module29, any: {[:messages], [body: "hi"]})

      assert query.filter == [{:any, {[:messages], [{:body, :==, "hi"}]}}]
    end

    test "quantifies with no condition" do
      query = filter(Module26, any: {[:messages], []})

      assert query.filter == [{:any, {[:messages], []}}]
    end

    test "quantifies with none" do
      query = filter(Module26, none: {[:messages], [body: "hi"]})

      assert query.filter == [{:none, {[:messages], [{:body, :==, "hi"}]}}]
    end

    test "quantifies with all" do
      query = filter(Module26, all: {[:messages], [position: {:>, 1}]})

      assert query.filter == [{:all, {[:messages], [{:position, :>, 1}]}}]
    end

    test "quantifies over a set reached through a to-one" do
      query = filter(Module28, any: {[:channel, :messages], [body: "hi"]})

      assert query.filter == [{:any, {[:channel, :messages], [{:body, :==, "hi"}]}}]
    end

    test "quantifies inside a quantifier's condition, over the related row's set" do
      query = filter(Module26, any: {[:messages], [any: {[:labels], [name: "urgent"]}]})

      assert query.filter == [
               {:any, {[:messages], [{:any, {[:labels], [{:name, :==, "urgent"}]}}]}}
             ]
    end

    test "reads a path of the related row" do
      query = filter(Module26, any: {[:messages], [{[:channel, :name], "general"}]})

      assert query.filter == [{:any, {[:messages], [{[:channel, :name], :==, "general"}]}}]
    end

    test "reads an attribute of the row above on the left" do
      query = filter(Module26, any: {[:messages], [{{:outer, 1, :name}, "general"}]})

      assert query.filter == [{:any, {[:messages], [{{:outer, 1, :name}, :==, "general"}]}}]
    end

    test "reads a path of the row above" do
      query = filter(Module28, any: {[:labels], [{{:outer, 1, [:channel, :name]}, "general"}]})

      assert query.filter == [
               {:any, {[:labels], [{{:outer, 1, [:channel, :name]}, :==, "general"}]}}
             ]
    end

    test "compares an attribute with the same attribute of the row above" do
      query =
        filter(Module28,
          any: {[:channel, :messages], [position: {:>, {:attribute, {:outer, 1, :position}}}]}
        )

      assert query.filter == [
               {:any,
                {[:channel, :messages], [{:position, :>, {:attribute, {:outer, 1, :position}}}]}}
             ]
    end

    test "compares two enums of two rows declaring the same values" do
      query =
        filter(Module31, any: {[:items], [priority: {:>=, {:attribute, {:outer, 1, :floor}}}]})

      assert query.filter == [
               {:any, {[:items], [{:priority, :>=, {:attribute, {:outer, 1, :floor}}}]}}
             ]
    end

    test "reads a set of the row above, counting levels by nesting inside it" do
      query =
        filter(Module28,
          any: {[:labels], [any: {{:outer, 1, [:labels]}, [{{:outer, 2, :body}, "x"}]}]}
        )

      assert query.filter == [
               {:any,
                {[:labels], [{:any, {{:outer, 1, [:labels]}, [{{:outer, 2, :body}, :==, "x"}]}}]}}
             ]
    end

    test "reads the queried row two quantifiers out" do
      query =
        filter(Module26,
          any: {[:messages], [any: {[:labels], [name: {:attribute, {:outer, 2, :name}}]}]}
        )

      assert query.filter == [
               {:any,
                {[:messages],
                 [{:any, {[:labels], [{:name, :==, {:attribute, {:outer, 2, :name}}}]}}]}}
             ]
    end

    test "takes a quantifier as an alternative of a disjunction" do
      query = filter(Module26, or: [[name: "general"], [any: {[:messages], []}]])

      assert query.filter == [{:or, [[{:name, :==, "general"}], [{:any, {[:messages], []}}]]}]
    end

    test "keeps an attribute named like a quantifier an attribute" do
      defmodule AnyAttributeFixture do
        use Hologram.Entity

        attribute :any, :boolean, default: false
      end

      query = filter(AnyAttributeFixture, any: true, any: {:!=, false})

      assert query.filter == [{:any, :==, true}, {:any, :!=, false}]
    end

    test "raises on a source ending at a to-one relationship" do
      expected_msg =
        ":channel is a to-one relationship in Hologram.Test.Fixtures.Entity.Module28 - any, none and all ask about the rows of a to-many relationship - compare the related row through a path: channel.<attribute>"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module28, any: {[:channel], []})
      end
    end

    test "raises on a source ending at a single inverse" do
      expected_msg =
        ":topic is an inverse relationship holding one row in Hologram.Test.Fixtures.Entity.Module26 - any, none and all ask about the rows of a to-many relationship"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module26, any: {[:topic], []})
      end
    end

    test "raises on a source going through a to-many relationship" do
      expected_msg =
        ":labels is a to-many relationship in Hologram.Test.Fixtures.Entity.Module28 - a quantifier's source goes through to-one relationships to one set - quantify each set with a quantifier of its own"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module28, any: {[:labels, :messages], []})
      end
    end

    test "raises on a source going through an inverse relationship" do
      expected_msg =
        ":messages is an inverse relationship in Hologram.Test.Fixtures.Entity.Module26 - a quantifier's source goes through to-one relationships that hold their reference to a set"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module26, any: {[:messages, :labels], []})
      end
    end

    test "raises on a source going through an attribute" do
      expected_msg =
        ":body is an attribute in Hologram.Test.Fixtures.Entity.Module28 - a quantifier's source names relationships"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module28, any: {[:body, :messages], []})
      end
    end

    test "raises on a source going through an unknown relationship" do
      expected_msg =
        "unknown relationship :thread in Hologram.Test.Fixtures.Entity.Module28 - known relationships: :channel"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module28, any: {[:thread, :messages], []})
      end
    end

    test "raises on a source naming an attribute" do
      expected_msg =
        ":name is an attribute in Hologram.Test.Fixtures.Entity.Module26 - a quantifier's source names relationships"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module26, any: {[:name], []})
      end
    end

    test "raises on a source naming an unknown relationship" do
      expected_msg =
        "unknown relationship :posts in Hologram.Test.Fixtures.Entity.Module26 - known relationships: :messages, :topic"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module26, any: {[:posts], []})
      end
    end

    test "raises on an empty source" do
      expected_msg =
        "a quantifier's source is a list of relationship names, or {:outer, levels, list}, got: []"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module26, any: {[], []})
      end
    end

    test "raises on a source holding something other than relationship names" do
      expected_msg =
        ~s(a quantifier's source is a list of relationship names, or {:outer, levels, list}, got: ["messages"])

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module26, any: {["messages"], []})
      end
    end

    test "raises on a source the related row does not declare, naming the related type" do
      expected_msg =
        "unknown relationship :topic in Hologram.Test.Fixtures.Entity.Module28 - known relationships: :channel, :labels"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module26, any: {[:messages], [any: {[:topic], []}]})
      end
    end

    test "raises on all with no condition" do
      expected_msg =
        "all takes a condition - all over no condition says nothing, got: {[:messages], []}"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module26, all: {[:messages], []})
      end
    end

    test "raises on a condition that is not a list of name and value pairs" do
      expected_msg = "a quantifier's condition is a list of name and value pairs, got: [:body]"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module26, any: {[:messages], [:body]})
      end
    end

    test "raises on an unknown attribute of the related row" do
      expected_msg =
        "unknown attribute :title in Hologram.Test.Fixtures.Entity.Module28 - known attributes: :body, :channel_id, :created_at, :id, :position, :updated_at"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module26, any: {[:messages], [title: "x"]})
      end
    end

    test "raises on an attribute of the related row compared with itself" do
      expected_msg =
        "operator :== compares attribute :name in Hologram.Test.Fixtures.Entity.Module29 with itself"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module28, any: {[:labels], [name: {:attribute, :name}]})
      end
    end

    test "raises on an attribute of the row above compared with itself" do
      expected_msg =
        "operator :== compares attribute :name in Hologram.Test.Fixtures.Entity.Module26 with itself"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module26,
          any: {[:messages], [{{:outer, 1, :name}, {:attribute, {:outer, 1, :name}}}]}
        )
      end
    end

    test "raises on attributes of two rows having different types" do
      expected_msg =
        "operator :== compares attribute :name in Hologram.Test.Fixtures.Entity.Module29 with attribute :position in Hologram.Test.Fixtures.Entity.Module28, which have different types (:string and :integer) - two attributes compare when they have the same type, or when one widens to the other (:integer to :float)"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module28, any: {[:labels], [name: {:attribute, {:outer, 1, :position}}]})
      end
    end

    test "raises on enums of two rows declaring different values" do
      expected_msg =
        "operator :>= compares attribute :priority in Hologram.Test.Fixtures.Entity.Module17 with attribute :tier in Hologram.Test.Fixtures.Entity.Module31, which declare different values ([:low, :medium, :high] and [:low, :high]) - two enum attributes compare only when they declare the same values in the same order"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module31, any: {[:items], [priority: {:>=, {:attribute, {:outer, 1, :tier}}}]})
      end
    end

    test "raises on an unknown attribute of the row above" do
      expected_msg =
        "unknown attribute :title in Hologram.Test.Fixtures.Entity.Module26 - known attributes: :created_at, :id, :name, :updated_at"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module26, any: {[:messages], [{{:outer, 1, :title}, "x"}]})
      end
    end

    test "raises on a name of a row above outside any quantifier" do
      expected_msg =
        "{:outer, 1, :name} names no row above the condition it stands in, which has no row above it - {:outer, levels, name} reads the row levels quantifiers out, from 1 up to the queried row"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module26, [{{:outer, 1, :name}, "general"}])
      end
    end

    test "raises on a name of a row above reaching past the queried row" do
      expected_msg =
        "{:outer, 2, :name} names no row above the condition it stands in, which has 1 row above it - {:outer, levels, name} reads the row levels quantifiers out, from 1 up to the queried row"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module26, any: {[:messages], [{{:outer, 2, :name}, "general"}]})
      end
    end

    test "raises on a key naming a row zero levels out" do
      expected_msg =
        "{:outer, 0, :name} names no row above the condition it stands in, which has 1 row above it - {:outer, levels, name} reads the row levels quantifiers out, from 1 up to the queried row"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module26, any: {[:messages], [{{:outer, 0, :name}, "x"}]})
      end
    end

    test "raises on a malformed attribute operand of a row above, quoting it as written" do
      expected_msg =
        ~s(invalid attribute operand {:attribute, {:outer, 1, "name"}} - an attribute is named by an atom, and a path by a list of two or more atoms)

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module26, any: {[:messages], [body: {:attribute, {:outer, 1, "name"}}]})
      end
    end

    test "raises on a source of a row above naming no relationship" do
      expected_msg =
        "a quantifier's source is a list of relationship names, or {:outer, levels, list}, got: {:outer, 1, []}"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module26, any: {[:messages], [any: {{:outer, 1, []}, []}]})
      end
    end

    test "raises on a name of a row zero levels out" do
      expected_msg =
        "{:outer, 0, :name} names no row above the condition it stands in, which has 1 row above it - {:outer, levels, name} reads the row levels quantifiers out, from 1 up to the queried row"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module26, any: {[:messages], [body: {:attribute, {:outer, 0, :name}}]})
      end
    end

    test "raises on a source of a row above reaching past the queried row" do
      expected_msg =
        "{:outer, 2, [:messages]} names no row above the condition it stands in, which has 1 row above it - {:outer, levels, name} reads the row levels quantifiers out, from 1 up to the queried row"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module26, any: {[:messages], [any: {{:outer, 2, [:messages]}, []}]})
      end
    end
  end

  describe "include/3" do
    test "includes an inverse set" do
      query = include(Module26, :messages)

      assert query.include == %{messages: base_term(Module28)}
    end

    test "includes a single inverse" do
      query = include(Module26, :topic)

      assert query.include == %{topic: base_term(Module27)}
    end

    test "includes an inverse of a to-many" do
      query = include(Module29, :messages)

      assert query.include == %{messages: base_term(Module28)}
    end

    test "merges two includes of one inverse" do
      query =
        Module26
        |> include(:messages)
        |> include(:messages)

      assert query.include == %{messages: base_term(Module28)}
    end

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
      assert include(Module3, :a) == %Query{entity: Module3, include: %{a: base_term(Module2)}}
    end

    test "embeds a to-one relationship" do
      query = include(Module3, :c)

      assert query.include == %{c: base_term(Module1)}
    end

    test "includes several relationships from a list spec" do
      query = include(Module3, [:a, :b])

      assert query.include == %{a: base_term(Module2), b: base_term(Module2)}
    end

    test "includes three levels deep" do
      query =
        include(Module5, :b, fn level_1 ->
          include(level_1, :b, fn level_2 ->
            include(level_2, :b)
          end)
        end)

      assert query.include == %{
               b: %Query{
                 entity: Module5,
                 include: %{b: %Query{entity: Module5, include: %{b: base_term(Module5)}}}
               }
             }
    end

    test "merges a repeated include at the second level" do
      query =
        Module5
        |> include(a: :a)
        |> include(a: :a)

      assert query.include == %{a: %{base_term(Module3) | include: %{a: base_term(Module2)}}}
    end

    test "merges a repeated include of a relationship" do
      query =
        Module3
        |> include(:a)
        |> include(:a)

      assert query == %Query{entity: Module3, include: %{a: base_term(Module2)}}
    end

    test "merges a second include that narrows a nested relationship" do
      query =
        Module5
        |> include(:a)
        |> include(a: [a: &filter(&1, a: true)])

      expected_nested = %{base_term(Module2) | filter: [{:a, :==, true}]}

      assert query.include == %{a: %{base_term(Module3) | include: %{a: expected_nested}}}
    end

    test "merges includes repeated in one list spec" do
      query = include(Module5, a: :a, a: :b)

      assert query.include == %{
               a: %{base_term(Module3) | include: %{a: base_term(Module2), b: base_term(Module2)}}
             }
    end

    test "merges includes whose nested branches differ in clauses" do
      query =
        Module5
        |> include(a: [a: &filter(&1, a: true)])
        |> include(a: :b)

      expected_nested = %{base_term(Module2) | filter: [{:a, :==, true}]}

      assert query.include == %{
               a: %{base_term(Module3) | include: %{a: expected_nested, b: base_term(Module2)}}
             }
    end

    test "merges what two includes of a relationship include" do
      query =
        Module5
        |> include(a: :a)
        |> include(a: :b)

      assert query.include == %{
               a: %{base_term(Module3) | include: %{a: base_term(Module2), b: base_term(Module2)}}
             }
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
          |> sort(:c)
        end)

      expected_sub_term = %{
        base_term(Module2)
        | filter: [{:a, :==, false}],
          sort: [{:c, :asc}]
      }

      assert query.include == %{a: expected_sub_term}
    end

    test "raises on a non-function sub-builder" do
      expected_msg =
        "include sub-builder for relationship :a must be a one-argument function, got: 5"

      assert_error ArgumentError, expected_msg, fn ->
        include(Module3, :a, wrap_term(5))
      end
    end

    test "raises on a repeated include at the second level when one side has clauses" do
      expected_msg = "relationship :a is already included"

      assert_error ArgumentError, expected_msg, fn ->
        Module5
        |> include(a: [a: &filter(&1, a: true)])
        |> include(a: :a)
      end
    end

    test "raises on a repeated include when the included one has clauses" do
      expected_msg = "relationship :a is already included"

      assert_error ArgumentError, expected_msg, fn ->
        Module3
        |> include(:a, &filter(&1, a: true))
        |> include(:a)
      end
    end

    test "raises on a repeated include when the new one has clauses" do
      expected_msg = "relationship :a is already included"

      assert_error ArgumentError, expected_msg, fn ->
        Module3
        |> include(:a)
        |> include(:a, &filter(&1, a: true))
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

    # The root's mark already reads the whole query on the server's authority, includes and all,
    # so a sub-term marking one of its own would say nothing the read honours.
    test "raises on a sub-term carrying a trust mark" do
      expected_msg =
        "include sub-terms take no trust mark - trust/1 goes on the query root and reads the whole query, includes and all, on the server's authority"

      assert_error ArgumentError, expected_msg, fn ->
        include(Module3, :a, &trust/1)
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

    test "raises on clauses for a single inverse" do
      expected_msg =
        "to-one relationship :topic takes no clauses - clauses apply to to-many includes"

      assert_error ArgumentError, expected_msg, fn ->
        include(Module26, :topic, &filter(&1, summary: "x"))
      end
    end

    test "raises on an unknown relationship, naming the inverses among the known ones" do
      defmodule KnownRelationshipsFixture do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module28

        relationship :a, Module1
        relationship :b, [Module28], inverse: channel
        relationship :c, Module1
      end

      expected_msg =
        "unknown relationship :x in Hologram.Query.StageTest.KnownRelationshipsFixture - known relationships: :a, :b, :c"

      assert_error ArgumentError, expected_msg, fn ->
        include(KnownRelationshipsFixture, :x)
      end
    end

    test "raises on a second include of an inverse when either carries clauses" do
      assert_error ArgumentError, "relationship :messages is already included", fn ->
        Module26
        |> include(:messages)
        |> include(:messages, &filter(&1, body: "x"))
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
  end

  describe "increment/3" do
    test "records a positive amount as a delta" do
      entity = Module10.new(count: 5)

      result = increment(entity, :count, 2)

      assert result.__meta__ == %Metadata{attribute_ops: %{count: {:increment, 2}}}
    end

    test "previews the result on the struct's field" do
      entity = Module10.new(count: 5)

      result = increment(entity, :count, 2)

      assert result.count == 7
    end

    test "previews a second move on top of the first" do
      result =
        %{count: 5}
        |> Module10.new()
        |> increment(:count, 2)
        |> decrement(:count, 1)

      assert result.count == 6
    end

    test "moves down by a negative amount" do
      entity = Module10.new(count: 5)

      result = increment(entity, :count, -2)

      assert result.__meta__ == %Metadata{attribute_ops: %{count: {:increment, -2}}}
    end

    test "records nothing for a zero amount" do
      entity = Module10.new(count: 5)

      result = increment(entity, :count, 0)

      assert result.__meta__ == %Metadata{}
    end

    test "adds a second increment to the first" do
      result =
        %{count: 5}
        |> Module10.new()
        |> increment(:count, 2)
        |> increment(:count, 3)

      assert result.__meta__ == %Metadata{attribute_ops: %{count: {:increment, 5}}}
    end

    test "keeps the rest of the metadata" do
      result =
        %{count: 5}
        |> Module10.new()
        |> put_attribute(bio: "x")
        |> increment(:count, 1)

      assert result.__meta__.attribute_ops == %{bio: {:put, "x"}, count: {:increment, 1}}
    end

    test "folds into a put value recorded before it" do
      result =
        %{count: 5}
        |> Module10.new()
        |> put_attribute(count: 10)
        |> increment(:count, 1)

      assert result.__meta__ == %Metadata{attribute_ops: %{count: {:put, 11}}}
      assert result.count == 11
    end

    test "raises on an amount that is not an integer" do
      entity = Module10.new(count: 5)

      assert_error ArgumentError, "increment takes an integer amount, got: 1.5", fn ->
        increment(entity, :count, 1.5)
      end

      assert_error ArgumentError, ~s(increment takes an integer amount, got: "1"), fn ->
        increment(entity, :count, "1")
      end
    end

    test "raises on an optional integer attribute" do
      entity = Module10.new(count: 5)

      expected_msg =
        ":priority in Hologram.Test.Fixtures.Entity.Module10 is optional and can hold nil - increment moves attributes that always hold a number - declare it without optional: true, with a default"

      assert_error ArgumentError, expected_msg, fn ->
        increment(entity, :priority, 1)
      end
    end

    test "raises on a non-integer attribute" do
      entity = Module10.new(count: 5)

      expected_msg =
        ":bio is a :string attribute of Hologram.Test.Fixtures.Entity.Module10 - increment moves integer attributes only"

      assert_error ArgumentError, expected_msg, fn ->
        increment(entity, :bio, 1)
      end
    end

    test "raises on a relationship" do
      entity = Module3.new()

      expected_msg =
        ":b is a relationship in Hologram.Test.Fixtures.Entity.Module3 - increment moves integer attributes only"

      assert_error ArgumentError, expected_msg, fn ->
        increment(entity, :b, 1)
      end
    end

    test "raises on a system attribute" do
      entity = Module10.new(count: 5)

      expected_msg =
        ":id is a system attribute of Hologram.Test.Fixtures.Entity.Module10 - it is managed automatically and can't be moved"

      assert_error ArgumentError, expected_msg, fn ->
        increment(entity, :id, 1)
      end
    end

    test "raises on an unknown name" do
      entity = Module10.new(count: 5)

      expected_msg =
        "unknown attribute :nope in Hologram.Test.Fixtures.Entity.Module10 - known counters: :count"

      assert_error ArgumentError, expected_msg, fn ->
        increment(entity, :nope, 1)
      end
    end

    test "raises when the entity is not an entity struct" do
      assert_error ArgumentError, ~s(increment takes an entity struct, got: "x"), fn ->
        increment(wrap_term("x"), :count, 1)
      end
    end

    test "raises when the struct's field holds nil" do
      entity = Module10.new()

      expected_msg =
        ":count in Hologram.Test.Fixtures.Entity.Module10 holds nil - a counter always holds a number, so there is nothing for increment to move - read the row first, or give the attribute a default"

      assert_error ArgumentError, expected_msg, fn ->
        increment(entity, :count, 1)
      end
    end

    test "raises when the put value it would fold into is not an integer" do
      entity = Module10.new(count: 5)

      expected_msg =
        ":count in Hologram.Test.Fixtures.Entity.Module10 carries a put value that is not an integer (nil) - increment cannot move it"

      assert_error ArgumentError, expected_msg, fn ->
        entity
        |> put_attribute(count: nil)
        |> increment(:count, 1)
      end
    end
  end

  describe "inspect_name/1" do
    test "spells an attribute as inspect does" do
      assert inspect_name(:archived) == ":archived"
    end

    test "spells a path as it is written" do
      assert inspect_name([:channel, :org, :name]) == "channel.org.name"
    end

    test "spells a name of a row above as the name it carries" do
      assert inspect_name({:outer, 1, :archived}) == ":archived"
      assert inspect_name({:outer, 2, [:channel, :name]}) == "channel.name"
    end
  end

  describe "normalize/1" do
    test "orders an included inverse set by its declared order, then by id" do
      query =
        Module26
        |> include(:messages)
        |> normalize()

      assert query.include.messages.sort == [{:position, :asc}, {:id, :asc}]
    end

    test "orders an included inverse set by the include's own order over the declared one" do
      query =
        Module26
        |> include(:messages, &sort(&1, :body))
        |> normalize()

      assert query.include.messages.sort == [{:body, :asc}, {:id, :asc}]
    end

    test "orders an included inverse set by a declared list, directions kept, then by id" do
      defmodule DeclaredListOrderFixture do
        use Hologram.Entity

        alias Hologram.Test.Fixtures.Entity.Module28

        relationship :messages, [Module28], inverse: channel, sort: [position: :desc, body: :asc]
      end

      query =
        DeclaredListOrderFixture
        |> include(:messages)
        |> normalize()

      assert query.include.messages.sort == [{:position, :desc}, {:body, :asc}, {:id, :asc}]
    end

    test "normalizes a term including an inverse the same way twice" do
      query =
        Module26
        |> include(:messages)
        |> normalize()

      assert normalize(query) == query
    end

    test "orders an included inverse set declaring no order by id" do
      query =
        Module29
        |> include(:messages)
        |> normalize()

      assert query.include.messages.sort == [{:id, :asc}]
    end

    test "gives an included single inverse no order" do
      query =
        Module26
        |> include(:topic)
        |> normalize()

      assert query.include.topic.sort == []
    end

    test "appends an ascending id tiebreaker after a placeholder ordering key" do
      query =
        Module2
        |> sort(%Placeholder{name: :sort})
        |> normalize()

      assert query.sort == [{{:placeholder, :sort}, :asc}, {:id, :asc}]
    end

    test "appends an ascending id tiebreaker to orderings" do
      query =
        Module2
        |> sort(:c)
        |> normalize()

      assert query.sort == [{:c, :asc}, {:id, :asc}]
    end

    test "defaults an empty ordering to the id order" do
      assert normalize(Module2) == %Query{entity: Module2, sort: [{:id, :asc}]}
    end

    test "drops the ordering from counting queries" do
      query =
        Module2
        |> sort(:c)
        |> count()
        |> normalize()

      assert query.sort == []
    end

    test "is idempotent" do
      normalized =
        Module3
        |> filter(id: "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f")
        |> filter(
          or: [
            [c_id: "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e1f"],
            [b_id: "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e2f"]
          ]
        )
        |> include(:a)
        |> sort(:created_at)
        |> normalize()

      assert normalize(normalized) == normalized
    end

    test "keeps a trust mark" do
      query =
        Module2
        |> trust()
        |> normalize()

      assert query.trust == true
    end

    test "leaves orderings already keyed by id untouched" do
      query =
        Module2
        |> sort(id: :desc)
        |> normalize()

      assert query.sort == [{:id, :desc}]
    end

    test "normalizes includes nested under a to-one include" do
      query =
        Module5
        |> include(a: :a)
        |> normalize()

      nested_sub_term = query.include.a.include.a

      assert query.include.a.sort == []
      assert nested_sub_term.sort == [{:id, :asc}]
    end

    test "normalizes to-many sub-terms" do
      query =
        Module3
        |> include(:a, &filter(&1, c: "x", a: true))
        |> normalize()

      assert query.include.a.filter == [{:a, :==, true}, {:c, :==, "x"}]
      assert query.include.a.sort == [{:id, :asc}]
    end

    test "skips ordering for to-one includes" do
      query =
        Module3
        |> include(:c)
        |> normalize()

      assert query.include.c.sort == []
    end

    test "sorts a disjunction before the predicates beside it" do
      query =
        Module2
        |> filter(a: true)
        |> filter(or: [[c: "x"], [b: 1]])
        |> normalize()

      assert query.filter == [{:or, [[{:b, :==, 1}], [{:c, :==, "x"}]]}, {:a, :==, true}]
    end

    test "sorts filter predicates canonically" do
      query =
        Module2
        |> filter(c: "x", a: true)
        |> normalize()

      assert query.filter == [{:a, :==, true}, {:c, :==, "x"}]
    end

    test "sorts the alternatives of a disjunction and the predicates inside them" do
      query =
        Module2
        |> filter(or: [[c: "x"], [b: 1, a: true]])
        |> normalize()

      assert query.filter == [{:or, [[{:a, :==, true}, {:b, :==, 1}], [{:c, :==, "x"}]]}]
    end

    test "sorts quantifiers among disjunctions, before the predicates beside them" do
      query =
        Module26
        |> filter(name: "general")
        |> filter(or: [[name: "b"], [name: "a"]])
        |> filter(none: {[:messages], [position: 2, body: "b"]}, any: {[:messages], []})
        |> normalize()

      assert query.filter == [
               {:any, {[:messages], []}},
               {:none, {[:messages], [{:body, :==, "b"}, {:position, :==, 2}]}},
               {:or, [[{:name, :==, "a"}], [{:name, :==, "b"}]]},
               {:name, :==, "general"}
             ]

      assert normalize(query) == query
    end

    test "sorts a nested quantifier's predicates" do
      query =
        Module26
        |> filter(any: {[:messages], [any: {[:labels], [name: "b", id: "a"]}]})
        |> normalize()

      assert query.filter == [
               {:any, {[:messages], [{:any, {[:labels], [{:id, :==, "a"}, {:name, :==, "b"}]}}]}}
             ]

      assert normalize(query) == query
    end
  end

  describe "normalized_filter/1" do
    test "leaves a sorted filter as it is" do
      filter = [{:or, [[{:a, :==, true}], [{:b, :==, 1}]]}, {:c, :==, "x"}]

      assert normalized_filter(filter) == filter
    end

    test "sorts nested disjunctions recursively" do
      filter = [
        {:c, :==, 1},
        {:or, [[{:b, :==, 2}, {:or, [[{:z, :==, 1}], [{:y, :==, 1}]]}], [{:a, :==, 3}]]}
      ]

      assert normalized_filter(filter) == [
               {:or, [[{:or, [[{:y, :==, 1}], [{:z, :==, 1}]]}, {:b, :==, 2}], [{:a, :==, 3}]]},
               {:c, :==, 1}
             ]
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
      assert one(Module2) == %Query{cardinality: :one, entity: Module2}
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

  describe "paginate/2" do
    test "accepts a placeholder page" do
      query = paginate(Module2, page: %Placeholder{name: :page}, size: 20)

      assert query.skip == {:placeholder, :page}
      assert query.take == 20
    end

    test "accepts a placeholder size" do
      query = paginate(Module2, page: 3, size: %Placeholder{name: :size})

      assert query.skip == {:placeholder, :size}
      assert query.take == {:placeholder, :size}
    end

    test "computes a zero skip for the first page" do
      query = paginate(Module2, page: 1, size: 20)

      assert query.take == 20
      assert query.skip == 0
    end

    test "replaces prior view bounds" do
      query =
        Module2
        |> take(10)
        |> paginate(page: 3, size: 20)

      assert query.take == 20
      assert query.skip == 40
    end

    test "sets the view bounds from page and size" do
      assert paginate(Module2, page: 3, size: 20) == %Query{
               entity: Module2,
               skip: 40,
               take: 20
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
        |> take(%Placeholder{name: :size})
        |> skip(%Placeholder{name: :start})
        |> sort([{%Placeholder{name: :sort}, %Placeholder{name: :dir}}])

      assert placeholder_names(query) == [:min_b, :field, :size, :start, :sort, :dir]
    end

    test "collects placeholders from include sub-terms" do
      query = include(Module3, :a, &filter(&1, c: %Placeholder{name: :owner}))

      assert placeholder_names(query) == [:owner]
    end

    test "collects placeholders inside a quantifier's condition" do
      query =
        filter(Module26,
          any:
            {[:messages],
             [body: %Placeholder{name: :body}, position: {:>, %Placeholder{name: :min}}]}
        )

      assert placeholder_names(query) == [:body, :min]
    end

    test "collects placeholders inside a disjunction" do
      query =
        filter(Module2,
          or: [[b: %Placeholder{name: :min}], [c: %Placeholder{name: :search}]]
        )

      assert placeholder_names(query) == [:min, :search]
    end

    test "yields an empty list for a concrete term" do
      assert placeholder_names(filter(Module2, a: true)) == []
    end
  end

  describe "predicate_references/1" do
    test "returns the compared attribute of every triple" do
      assert predicate_references([{:a, :==, true}, {:b, :>=, 3}]) == [{[], :a}, {[], :b}]
    end

    test "adds the attribute an operand names" do
      assert predicate_references([{:b, :<, {:attribute, :c}}, {:a, :==, true}]) ==
               [{[], :b}, {[], :c}, {[], :a}]
    end

    test "returns a path with the relationships it follows" do
      assert predicate_references([{[:a, :b, :c], :==, "x"}]) == [{[:a, :b], :c}]
    end

    test "returns the path an operand names" do
      assert predicate_references([{:c_id, :==, {:attribute, [:b, :id]}}]) ==
               [{[], :c_id}, {[:b], :id}]
    end

    test "walks the alternatives of a disjunction" do
      filter = [{:or, [[{:a, :==, true}], [{:b, :>=, {:attribute, :c}}]]}]

      assert predicate_references(filter) == [{[], :a}, {[], :b}, {[], :c}]
    end

    test "returns a quantifier's names with the relationships to the row each is read on" do
      filter = [
        {:any,
         {[:channel, :messages], [{:created_at, :>, {:attribute, {:outer, 1, :last_read_at}}}]}}
      ]

      assert predicate_references(filter) == [
               {[:channel, :messages], :created_at},
               {[], :last_read_at}
             ]
    end
  end

  describe "put_attribute/2" do
    test "accepts a map of values" do
      entity = Module2.new(c: "x")

      result = put_attribute(entity, %{b: 7})

      assert result.b == 7
      assert result.__meta__ == %Metadata{attribute_ops: %{b: {:put, 7}}}
    end

    test "keeps the rest of the metadata" do
      metadata = %Metadata{claim: :trust, relationship_ops: %{{:a, "x"} => :add}}
      entity = %{Module3.new() | __meta__: metadata}

      result = put_attribute(entity, b_id: Entity.generate_id())

      assert result.__meta__.claim == :trust
      assert result.__meta__.relationship_ops == %{{:a, "x"} => :add}
    end

    test "merges into the changes already recorded, the later value replacing the earlier" do
      result =
        %{c: "x"}
        |> Module2.new()
        |> put_attribute(a: true, c: "y")
        |> put_attribute(c: "z")

      assert result.c == "z"
      assert result.__meta__ == %Metadata{attribute_ops: %{a: {:put, true}, c: {:put, "z"}}}
    end

    test "sets a to-one reference field" do
      target_id = Entity.generate_id()
      entity = Module3.new()

      result = put_attribute(entity, b_id: target_id)

      assert result.b_id == target_id
      assert result.__meta__ == %Metadata{attribute_ops: %{b_id: {:put, target_id}}}
    end

    test "sets the values on the struct and records them as changes" do
      entity = Module2.new(c: "x")

      result = put_attribute(entity, a: true, c: "y")

      assert result.a == true
      assert result.c == "y"
      assert result.__meta__ == %Metadata{attribute_ops: %{a: {:put, true}, c: {:put, "y"}}}
    end

    test "replaces a delta recorded before it" do
      result =
        %{count: 5}
        |> Module10.new()
        |> increment(:count, 1)
        |> put_attribute(count: 10)

      assert result.__meta__ == %Metadata{attribute_ops: %{count: {:put, 10}}}
    end

    test "raises on a system attribute name" do
      entity = Module2.new(c: "x")

      expected_msg =
        ":id is a system attribute of Hologram.Test.Fixtures.Entity.Module2 - it is managed automatically and can't be put"

      assert_error ArgumentError, expected_msg, fn ->
        put_attribute(entity, id: Entity.generate_id())
      end
    end

    test "raises on a to-many relationship name" do
      entity = Module3.new()

      expected_msg =
        ":a is a relationship in Hologram.Test.Fixtures.Entity.Module3 - only attributes can be put - add its edges via add_relationship"

      assert_error ArgumentError, expected_msg, fn ->
        put_attribute(entity, a: [])
      end
    end

    test "raises on an inverse relationship name" do
      entity = Module26.new()

      expected_msg =
        ":messages is an inverse relationship in Hologram.Test.Fixtures.Entity.Module26 - only attributes can be put - it reads the channel_id reference of Hologram.Test.Fixtures.Entity.Module28, so write that instead"

      assert_error ArgumentError, expected_msg, fn ->
        put_attribute(entity, messages: [])
      end
    end

    test "raises on a to-one relationship name" do
      entity = Module3.new()

      expected_msg =
        ":c is a relationship in Hologram.Test.Fixtures.Entity.Module3 - only attributes can be put - set its reference via :c_id"

      assert_error ArgumentError, expected_msg, fn ->
        put_attribute(entity, c: Module1.new())
      end
    end

    test "raises on an unknown name" do
      entity = Module3.new()

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
      entity = Module2.new(c: "x")

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
      entity = Module2.new(c: "x")

      result = put_attribute(entity, :a, true)

      assert result.a == true
      assert result.__meta__ == %Metadata{attribute_ops: %{a: {:put, true}}}
    end

    test "raises on an unknown name" do
      entity = Module2.new(c: "x")

      expected_msg =
        "unknown attribute :nope in Hologram.Test.Fixtures.Entity.Module2 - known attributes: :a, :b, :c"

      assert_error ArgumentError, expected_msg, fn ->
        put_attribute(entity, :nope, 1)
      end
    end
  end

  describe "quantified?/1" do
    test "holds for a quantifier" do
      assert quantified?([{:any, {[:messages], []}}])
    end

    test "holds for a quantifier inside an alternative" do
      assert quantified?([{:or, [[{:a, :==, 1}], [{:none, {[:messages], []}}]]}])
    end

    test "fails for predicates and disjunctions alone" do
      refute quantified?([{:a, :==, 1}, {:or, [[{:b, :==, 2}], [{:c, :==, 3}]]}])
    end

    test "fails for an attribute named like a quantifier" do
      refute quantified?([{:any, :==, true}])
    end
  end

  describe "relationship_chains/1" do
    test "returns a quantifier's relationship" do
      assert relationship_chains([{:any, {[:messages], []}}]) == [[:messages]]
    end

    test "returns a quantifier's path and what its condition follows behind it" do
      filter = [
        {:any, {[:channel, :messages], [{[:author, :name], :==, "ada"}]}}
      ]

      assert relationship_chains(filter) == [
               [:channel, :messages],
               [:channel, :messages, :author]
             ]
    end

    test "returns nested quantifiers' relationships behind their parents'" do
      filter = [{:any, {[:channels], [{:none, {[:messages], []}}]}}]

      assert relationship_chains(filter) == [[:channels], [:channels, :messages]]
    end

    test "returns a source read on a row above behind that row's relationships" do
      filter = [{:any, {[:follows], [{:any, {{:outer, 1, [:replies]}, []}}]}}]

      assert relationship_chains(filter) == [[:follows], [:replies]]
    end

    test "returns the relationships of paths, operands and alternatives, each once" do
      filter = [
        {[:trip, :name], :==, "a"},
        {:or, [[{:a, :==, {:attribute, [:trip, :leg, :b]}}], [{[:trip, :name], :==, "b"}]]}
      ]

      assert relationship_chains(filter) == [[:trip], [:trip, :leg]]
    end

    test "returns nothing for attributes of the queried row" do
      filter = [{:a, :==, {:attribute, :b}}, {{:placeholder, :k}, :==, 1}]

      assert relationship_chains(filter) == []
    end

    test "returns a source read on a row above behind the relationships to that row" do
      filter = [
        {:any,
         {[:channels],
          [{:any, {[:messages], [{:any, {{:outer, 1, [:labels]}, [{:name, :==, "x"}]}}]}}]}}
      ]

      assert relationship_chains(filter) == [
               [:channels],
               [:channels, :messages],
               [:channels, :labels]
             ]
    end

    test "returns the relationships of a path a name of a row above follows" do
      filter = [{:any, {[:messages], [{:body, :==, {:attribute, {:outer, 1, [:org, :name]}}}]}}]

      assert relationship_chains(filter) == [[:messages], [:org]]
    end
  end

  describe "skip/2" do
    test "accepts a placeholder" do
      query = skip(Module2, %Placeholder{name: :start})

      assert query.skip == {:placeholder, :start}
    end

    test "replaces a prior skip" do
      query =
        Module2
        |> skip(20)
        |> skip(40)

      assert query.skip == 40
    end

    test "sets how many results it skips" do
      assert skip(Module2, 20) == %Query{entity: Module2, skip: 20}
    end

    test "raises on a negative count" do
      expected_msg = "skip must be a non-negative integer, got: -5"

      assert_error ArgumentError, expected_msg, fn ->
        skip(Module2, -5)
      end
    end
  end

  describe "sort/2" do
    test "accepts a keyword spec with directions" do
      query = sort(Module2, b: :desc, c: :asc)

      assert query.sort == [{:b, :desc}, {:c, :asc}]
    end

    test "accepts a mixed list of names and direction tuples" do
      query = sort(Module2, [:c, {:b, :desc}])

      assert query.sort == [{:c, :asc}, {:b, :desc}]
    end

    test "accepts a placeholder as a bare spec" do
      query = sort(Module2, %Placeholder{name: :sort})

      assert query.sort == [{{:placeholder, :sort}, :asc}]
    end

    test "accepts a placeholder as a direction" do
      query = sort(Module2, c: %Placeholder{name: :dir})

      assert query.sort == [{:c, {:placeholder, :dir}}]
    end

    test "accepts a placeholder as an ordering key" do
      query = sort(Module2, [{%Placeholder{name: :sort}, :desc}])

      assert query.sort == [{{:placeholder, :sort}, :desc}]
    end

    test "composes with filtering" do
      query =
        Module2
        |> filter(a: true)
        |> sort(:c)

      assert query.filter == [{:a, :==, true}]
      assert query.sort == [{:c, :asc}]
    end

    test "defaults a bare attribute name to ascending" do
      assert sort(Module2, :c) == %Query{entity: Module2, sort: [{:c, :asc}]}
    end

    test "defaults list entries to ascending" do
      query = sort(Module2, [:c, :a])

      assert query.sort == [{:c, :asc}, {:a, :asc}]
    end

    test "replaces a prior sort" do
      query =
        Module2
        |> sort(:c)
        |> sort(b: :desc)

      assert query.sort == [{:b, :desc}]
    end

    test "sorts by a system attribute" do
      query = sort(Module2, :created_at)

      assert query.sort == [{:created_at, :asc}]
    end

    # The declared `values:` list is the order, so nothing about an enum keeps it from being an
    # ordering key - both executors sort by a value's position in that list.
    test "sorts by an enum attribute" do
      query = sort(Module4, :c)

      assert query.sort == [{:c, :asc}]
    end

    test "raises on a non-atom spec" do
      expected_msg = "sort spec must be an attribute name or a list, got: 123"

      assert_error ArgumentError, expected_msg, fn ->
        sort(Module2, 123)
      end
    end

    test "raises on a relationship name" do
      expected_msg =
        ":c is a relationship in Hologram.Test.Fixtures.Entity.Module3 - only attributes can be ordered"

      assert_error ArgumentError, expected_msg, fn ->
        sort(Module3, :c)
      end
    end

    test "raises on an invalid direction" do
      expected_msg = "invalid direction :down for attribute :b - use :asc or :desc"

      assert_error ArgumentError, expected_msg, fn ->
        sort(Module2, b: :down)
      end
    end

    test "raises on an invalid entry" do
      expected_msg =
        "invalid sort entry 123 - use an attribute name or an {attribute, :asc | :desc} tuple"

      assert_error ArgumentError, expected_msg, fn ->
        sort(Module2, [123])
      end
    end

    test "raises on a to-one reference field" do
      expected_msg =
        "unknown attribute :c_id in Hologram.Test.Fixtures.Entity.Module3 - known attributes: :created_at, :id, :updated_at"

      assert_error ArgumentError, expected_msg, fn ->
        sort(Module3, :c_id)
      end
    end

    test "raises on an unknown attribute" do
      expected_msg =
        "unknown attribute :x in Hologram.Test.Fixtures.Entity.Module2 - known attributes: :a, :b, :c, :created_at, :id, :updated_at"

      assert_error ArgumentError, expected_msg, fn ->
        sort(Module2, :x)
      end
    end
  end

  describe "take/2" do
    test "accepts a placeholder" do
      query = take(Module2, %Placeholder{name: :size})

      assert query.take == {:placeholder, :size}
    end

    test "accepts zero" do
      query = take(Module2, 0)

      assert query.take == 0
    end

    test "composes with other stages" do
      query =
        Module2
        |> filter(a: true)
        |> take(50)

      assert query.filter == [{:a, :==, true}]
      assert query.take == 50
    end

    test "replaces a prior take" do
      query =
        Module2
        |> take(50)
        |> take(100)

      assert query.take == 100
    end

    test "sets how many results it takes" do
      assert take(Module2, 50) == %Query{entity: Module2, take: 50}
    end

    test "raises on a negative count" do
      expected_msg = "take must be a non-negative integer, got: -5"

      assert_error ArgumentError, expected_msg, fn ->
        take(Module2, -5)
      end
    end

    test "raises on a non-integer count" do
      expected_msg = "take must be a non-negative integer, got: 5.0"

      assert_error ArgumentError, expected_msg, fn ->
        take(Module2, wrap_term(5.0))
      end
    end
  end

  describe "triples/1" do
    test "returns the predicates of a flat filter unchanged" do
      filter = [{:a, :==, true}, {:b, :>=, 3}]

      assert triples(filter) == filter
    end

    test "walks nested disjunctions" do
      filter = [
        {:or, [[{:a, :==, true}, {:or, [[{:b, :==, 1}], [{:b, :==, 2}]]}], [{:c, :==, "x"}]]}
      ]

      assert triples(filter) == [{:a, :==, true}, {:b, :==, 1}, {:b, :==, 2}, {:c, :==, "x"}]
    end

    test "walks the alternatives of a disjunction in order" do
      filter = [{:or, [[{:a, :==, true}], [{:b, :>=, 3}, {:c, :==, "x"}]]}, {:d, :==, 1}]

      assert triples(filter) == [{:a, :==, true}, {:b, :>=, 3}, {:c, :==, "x"}, {:d, :==, 1}]
    end

    test "resolves a quantifier's names against the queried row" do
      filter = [
        {:any,
         {[:channel, :messages], [{:created_at, :>, {:attribute, {:outer, 1, :last_read_at}}}]}}
      ]

      assert triples(filter) == [
               {[:channel, :messages, :created_at], :>, {:attribute, :last_read_at}}
             ]
    end

    test "resolves a path a quantifier's condition reads and a name of the row above on the left" do
      filter = [
        {:any,
         {[:messages],
          [{[:author, :name], :==, "ada"}, {{:outer, 1, [:org, :name]}, :==, "acme"}]}}
      ]

      assert triples(filter) == [
               {[:messages, :author, :name], :==, "ada"},
               {[:org, :name], :==, "acme"}
             ]
    end

    test "resolves the names of nested quantifiers against the rows they reach" do
      filter = [
        {:any,
         {[:channels],
          [
            {:any,
             {[:messages],
              [
                {:created_at, :>, {:attribute, {:outer, 1, :archived_at}}},
                {:body, :==, {:attribute, {:outer, 2, :name}}}
              ]}}
          ]}}
      ]

      assert triples(filter) == [
               {[:channels, :messages, :created_at], :>, {:attribute, [:channels, :archived_at]}},
               {[:channels, :messages, :body], :==, {:attribute, :name}}
             ]
    end

    test "resolves the names under a source read on a row above" do
      filter = [
        {:any, {[:follows], [{:any, {{:outer, 1, [:replies]}, [{:body, :==, "x"}]}}]}}
      ]

      assert triples(filter) == [{[:replies, :body], :==, "x"}]
    end

    test "resolves the names under a source read on a row above that lies below the queried row" do
      filter = [
        {:any,
         {[:channels],
          [{:any, {[:messages], [{:any, {{:outer, 1, [:labels]}, [{:name, :==, "x"}]}}]}}]}}
      ]

      assert triples(filter) == [{[:channels, :labels, :name], :==, "x"}]
    end

    test "keeps a placeholder key inside a quantifier's condition" do
      filter = [{:any, {[:messages], [{{:placeholder, :field}, :==, 1}]}}]

      assert triples(filter) == [{{:placeholder, :field}, :==, 1}]
    end
  end

  describe "trust/1" do
    test "keeps the rest of the metadata" do
      result =
        %{c: "x"}
        |> Module2.new()
        |> put_attribute(a: true)
        |> trust()

      assert result.__meta__.attribute_ops == %{a: {:put, true}}
      assert result.__meta__.claim == :trust
    end

    test "records the claim" do
      entity = Module2.new(c: "x")

      result = trust(entity)

      assert result.__meta__ == %Metadata{claim: :trust}
    end

    test "marks a query term as trusted, keeping its stages" do
      result =
        Module2
        |> filter(a: true)
        |> trust()

      assert result.filter == [{:a, :==, true}]
      assert result.trust == true
    end

    test "marks an entity type's query as trusted" do
      assert trust(Module2) == %Query{entity: Module2, trust: true}
    end

    test "raises on a trust mark in an include sub-term" do
      expected_msg =
        "include sub-terms take no trust mark - trust/1 goes on the query root and reads the whole query, includes and all, on the server's authority"

      assert_error ArgumentError, expected_msg, fn ->
        include(Module3, :b, &trust/1)
      end
    end

    test "raises when the subject is neither an entity struct, an entity type nor a query term" do
      expected_msg =
        ~s("x" is not an entity type module or a query term - a query starts from a module with the "use Hologram.Entity" directive)

      assert_error ArgumentError, expected_msg, fn ->
        trust(wrap_term("x"))
      end
    end

    test "raises when the struct already carries an authorize claim" do
      entity = Module2.new(c: "x")

      expected_msg =
        "Hologram.Test.Fixtures.Entity.Module2 already carries a claim ({:authorize, :update}) - a write claims exactly one authority"

      assert_error ArgumentError, expected_msg, fn ->
        entity
        |> authorize(:update)
        |> trust()
      end
    end

    test "raises when the struct already carries a trust claim" do
      entity = Module2.new(c: "x")

      expected_msg =
        "Hologram.Test.Fixtures.Entity.Module2 already carries a claim (:trust) - a write claims exactly one authority"

      assert_error ArgumentError, expected_msg, fn ->
        entity
        |> trust()
        |> trust()
      end
    end
  end

  describe "written_names/1" do
    test "returns the keys of a predicate list" do
      assert written_names(a: true, b: {:>=, 3}) == [:a, :b]
    end

    test "adds the name an operand carries, bare or under an operator" do
      assert written_names(a: {:attribute, :b}, c: {:<, {:attribute, :d}}) == [:a, :b, :c, :d]
    end

    test "walks the lists of an or entry" do
      assert written_names(a: 1, or: [[b: 2], [c: {:attribute, :d}]]) == [:a, :b, :c, :d]
    end

    test "returns a path as its list" do
      assert written_names([{[:a, :b], {:==, {:attribute, [:c, :d]}}}]) == [[:a, :b], [:c, :d]]
    end

    test "returns or for an or entry that is not a list of lists" do
      assert written_names(or: [1, 2]) == [:or]
    end

    test "passes over a list that is not a path" do
      assert written_names([{[%Placeholder{name: :field}, :x], {:attribute, [:y]}}, a: 1]) == [:a]
    end

    test "passes over a placeholder key" do
      assert written_names([{%Placeholder{name: :field}, 1}]) == []
    end

    test "returns a quantifier's relationship, not the names of its condition" do
      assert written_names(any: {[:messages], [body: "x"]}) == [:messages]
    end

    test "returns a quantifier's path as its list" do
      assert written_names(none: {[:channel, :messages], []}) == [[:channel, :messages]]
    end

    test "passes over a quantifier read on a row above" do
      assert written_names(any: {{:outer, 1, [:messages]}, []}) == []
    end

    test "passes over a quantifier with no relationship" do
      assert written_names(any: {[], []}) == []
    end

    test "returns an attribute named like a quantifier holding an operator tuple" do
      assert written_names(any: {:in, [1, 2]}) == [:any]
    end
  end
end
