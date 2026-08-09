defmodule Hologram.QueryRunTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.Query

  alias Hologram.DB
  alias Hologram.Entity
  alias Hologram.Query.Param
  alias Hologram.Test.Fixtures.Entity.Module2

  defp create_module_2_entity(values) do
    Module2
    |> Entity.new(values)
    |> DB.create()
  end

  describe "get/2" do
    test "returns the entity with the given id" do
      created_entity = create_module_2_entity(a: true, c: "some text")

      assert get(Module2, created_entity.id).id == created_entity.id
    end

    test "returns nil when no entity matches" do
      assert get(Module2, Entity.generate_id()) == nil
    end

    test "raises on a non-canonical id" do
      expected_msg =
        "invalid id \"garbage\" for get - entity ids are canonical lowercase 8-4-4-4-12 UUID strings"

      assert_error ArgumentError, expected_msg, fn -> get(Module2, "garbage") end

      compact_id = "018f4571a1b27c3d8e4f5a6b7c8d9e0f"

      expected_compact_msg =
        "invalid id #{inspect(compact_id)} for get - entity ids are canonical lowercase 8-4-4-4-12 UUID strings"

      assert_error ArgumentError, expected_compact_msg, fn -> get(Module2, compact_id) end
    end
  end

  describe "run/1" do
    test "runs a set query and returns entity structs" do
      create_module_2_entity(a: true, c: "bbb")
      create_module_2_entity(a: false, c: "aaa")

      results =
        Module2
        |> order_by(:c)
        |> run()

      assert [%Module2{c: "aaa"}, %Module2{c: "bbb"}] = results
    end

    test "runs a bare entity type as the whole set" do
      create_module_2_entity(a: true, c: "some text")

      assert [%Module2{c: "some text"}] = run(Module2)
    end

    test "runs a single-result query" do
      created_entity = create_module_2_entity(a: true, c: "some text")

      found_entity =
        Module2
        |> filter(id: created_entity.id)
        |> one()
        |> run()

      assert found_entity.id == created_entity.id

      missing_entity =
        Module2
        |> filter(id: Entity.generate_id())
        |> one()
        |> run()

      assert missing_entity == nil
    end

    test "runs a counting query" do
      create_module_2_entity(a: true, c: "x")
      create_module_2_entity(a: true, c: "y")
      create_module_2_entity(a: false, c: "z")

      count =
        Module2
        |> filter(a: true)
        |> count()
        |> run()

      assert count == 2
    end

    test "raises on a query term containing params" do
      expected_msg =
        "cannot run a query term containing params - param :min_b has no value: directly executed queries embed concrete runtime values, params exist only in compiler-registered queries"

      assert_error ArgumentError, expected_msg, fn ->
        Module2
        |> filter(b: {:>=, %Param{name: :min_b}})
        |> run()
      end
    end
  end
end
