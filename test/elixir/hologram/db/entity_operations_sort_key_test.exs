defmodule Hologram.DB.EntityOperationsSortKeyTest do
  use Hologram.Test.DatabaseCase, async: false

  import Hologram.DB.EntityOperations, only: [create: 1, get: 2, update: 3]

  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.Entity
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module7

  defp companion_value(table, id) do
    sql = ~s(SELECT "c_$sort" FROM "hologram_data"."#{table}" WHERE "id" = $1)

    {:ok, %{rows: [[value]]}} = Connection.query(sql, [Codec.encode(id, :uuid)])

    value
  end

  describe "create/1" do
    test "derives a nil companion from a nil attribute value" do
      {:ok, entity} =
        Module7
        |> Entity.new()
        |> create()

      assert companion_value("test_fixtures_entity_module7", entity.id) == nil
    end

    test "derives the sort-key companion from the attribute value" do
      {:ok, entity} =
        Module2
        |> Entity.new(c: "Łódź")
        |> create()

      assert companion_value("test_fixtures_entity_module2", entity.id) == "lodz"
    end
  end

  describe "get/2" do
    test "returns the entity without its sort-key companion" do
      {:ok, entity} =
        Module2
        |> Entity.new(c: "Łódź")
        |> create()

      assert get(Module2, entity.id) == entity
    end
  end

  describe "update/3" do
    test "leaves the companion untouched when the attribute does not change" do
      {:ok, entity} =
        Module2
        |> Entity.new(c: "Łódź")
        |> create()

      :ok = update(Module2, entity.id, %{a: true})

      assert companion_value("test_fixtures_entity_module2", entity.id) == "lodz"
    end

    test "recomputes the companion when the attribute changes" do
      {:ok, entity} =
        Module2
        |> Entity.new(c: "Łódź")
        |> create()

      :ok = update(Module2, entity.id, %{c: "Zürich"})

      assert companion_value("test_fixtures_entity_module2", entity.id) == "zurich"
    end
  end
end
