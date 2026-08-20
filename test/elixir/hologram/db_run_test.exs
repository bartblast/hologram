defmodule Hologram.DBRunTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.Query

  alias Hologram.DB
  alias Hologram.Entity
  alias Hologram.Query.Placeholder
  alias Hologram.Test.Fixtures.Entity.Module2

  defp create_module_2_entity(values) do
    Module2
    |> Entity.new(values)
    |> DB.create()
  end

  describe "run/1" do
    test "runs a set query and returns entity structs" do
      create_module_2_entity(a: true, c: "bbb")
      create_module_2_entity(a: false, c: "aaa")

      results =
        Module2
        |> order_by(:c)
        |> DB.run()

      assert [%Module2{c: "aaa"}, %Module2{c: "bbb"}] = results
    end

    test "runs a bare entity type as the whole set" do
      create_module_2_entity(a: true, c: "some text")

      assert [%Module2{c: "some text"}] = DB.run(Module2)
    end

    test "runs a single-result query" do
      created_entity = create_module_2_entity(a: true, c: "some text")

      found_entity =
        Module2
        |> filter(id: created_entity.id)
        |> one()
        |> DB.run()

      assert found_entity.id == created_entity.id

      missing_entity =
        Module2
        |> filter(id: Entity.generate_id())
        |> one()
        |> DB.run()

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
        |> DB.run()

      assert count == 2
    end

    test "raises on a query term containing placeholders" do
      expected_msg =
        "cannot run a query term containing placeholders - placeholder :min_b has no value: directly executed queries embed concrete runtime values, placeholders exist only in compiler-registered queries"

      assert_error ArgumentError, expected_msg, fn ->
        Module2
        |> filter(b: {:>=, %Placeholder{name: :min_b}})
        |> DB.run()
      end
    end

    test "raises on a query term ordered by a placeholder" do
      expected_msg =
        "cannot run a query term containing placeholders - placeholder :sort has no value: directly executed queries embed concrete runtime values, placeholders exist only in compiler-registered queries"

      assert_error ArgumentError, expected_msg, fn ->
        Module2
        |> order_by(%Placeholder{name: :sort})
        |> DB.run()
      end
    end
  end
end
