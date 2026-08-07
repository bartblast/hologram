defmodule Hologram.QueryTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Query

  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3

  describe "filter/2" do
    test "accepts system attribute names" do
      query = filter(Module2, id: "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f")

      assert query.filter == [{:id, :==, "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f"}]
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

    test "raises on a non-entity module query" do
      expected_msg =
        ~s(String is not an entity type module or a query term - a query starts from a module with the "use Hologram.Entity" directive)

      assert_error ArgumentError, expected_msg, fn ->
        filter(String, a: true)
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

    test "raises on non-keyword predicates" do
      expected_msg = "filter predicates must be a keyword list, got: [:a]"

      assert_error ArgumentError, expected_msg, fn ->
        filter(Module2, [:a])
      end
    end
  end
end
