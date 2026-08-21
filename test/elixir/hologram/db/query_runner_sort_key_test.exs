defmodule Hologram.DB.QueryRunnerSortKeyTest do
  use Hologram.Test.DatabaseCase, async: false
  use Hologram.Query

  import Hologram.DB.EntityOperations, only: [add_relationship: 4, create: 1]
  import Hologram.DB.QueryRunner

  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.DB.SortKey
  alias Hologram.Entity
  alias Hologram.Query
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3

  defp backfill_sort_keys do
    select_sql = ~s(SELECT "id", "c" FROM "hologram_data"."test_fixtures_entity_module2")

    update_sql =
      ~s(UPDATE "hologram_data"."test_fixtures_entity_module2" SET "c_$sort" = $1 WHERE "id" = $2)

    {:ok, %{rows: rows}} = Connection.query(select_sql, [])

    Enum.each(rows, fn [id, value] ->
      {:ok, _result} = Connection.query(update_sql, [SortKey.compute(value), id])
    end)

    :ok
  end

  defp companion_mapping do
    Mapper.derive!([Module1, Module2, Module3])
  end

  describe "run/3" do
    test "orders string attributes practically through sort-key companions" do
      Module2
      |> Entity.new(a: true, c: "Zürich")
      |> create()

      Module2
      |> Entity.new(a: true, c: "Łódź")
      |> create()

      Module2
      |> Entity.new(a: true, c: "apple")
      |> create()

      backfill_sort_keys()

      term =
        Module2
        |> order_by(:c)
        |> Query.normalize()

      assert [%{c: "apple"}, %{c: "Łódź"}, %{c: "Zürich"}] = run(term, companion_mapping())
    end

    test "skips sort-key companions when decoding embedded entities" do
      related =
        Module2
        |> Entity.new(a: true, c: "banana")
        |> create()

      target =
        Module1
        |> Entity.new()
        |> create()

      source =
        Module3
        |> Entity.new(c_id: target.id)
        |> create()

      :ok = add_relationship(Module3, source.id, :a, related.id)

      term =
        Module3
        |> include(:a)
        |> Query.normalize()

      assert [%Module3{a: [%Module2{c: "banana"}]}] = run(term, companion_mapping())
    end

    test "skips sort-key companions when decoding entities" do
      Module2
      |> Entity.new(a: true, c: "banana")
      |> create()

      term =
        Module2
        |> filter(c: "banana")
        |> Query.normalize()

      assert [%Module2{c: "banana"}] = run(term, companion_mapping())
    end
  end
end
