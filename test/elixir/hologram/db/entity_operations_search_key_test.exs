defmodule Hologram.DB.EntityOperationsSearchKeyTest do
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.DB.EntityOperations, only: [create: 1, get: 2, update: 3]

  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module7

  # 70 bytes folded, past the 64 the sort key keeps.
  @long_value String.duplicate("Zürich ", 10)

  @long_value_folded String.duplicate("zurich ", 10)

  defp search_key(table, id) do
    sql = ~s(SELECT "c_$search" FROM "hologram_data"."#{table}" WHERE "id" = $1)

    {:ok, %{rows: [[value]]}} = Connection.query(sql, [Codec.encode(id, :uuid)])

    value
  end

  describe "create/1" do
    test "derives a nil search key from a nil attribute value" do
      {:ok, entity} = create(Module7.new())

      assert search_key("test_fixtures_entity_module7", entity.id) == nil
    end

    test "derives a nil search key from a value whose folded form fits the sort key" do
      {:ok, entity} =
        %{c: "Łódź"}
        |> Module2.new()
        |> create()

      assert search_key("test_fixtures_entity_module2", entity.id) == nil
    end

    test "derives the whole folded value when it is longer than the sort key keeps" do
      {:ok, entity} =
        %{c: @long_value}
        |> Module2.new()
        |> create()

      assert search_key("test_fixtures_entity_module2", entity.id) == @long_value_folded
    end

    # 8 Hangul syllables are 24 bytes, and the 24 jamo they decompose into 72.
    test "derives the folded value of a short value that folds past the sort key's cap" do
      {:ok, entity} =
        %{c: String.duplicate("한", 8)}
        |> Module2.new()
        |> create()

      assert search_key("test_fixtures_entity_module2", entity.id) ==
               String.duplicate("\u1112\u1161\u11AB", 8)
    end
  end

  describe "get/2" do
    test "returns the entity without its search key" do
      {:ok, entity} =
        %{c: @long_value}
        |> Module2.new()
        |> create()

      assert get(Module2, entity.id) == entity
    end
  end

  describe "update/3" do
    test "recomputes the search key when the attribute changes" do
      {:ok, entity} =
        %{c: "Łódź"}
        |> Module2.new()
        |> create()

      :ok = update(Module2, entity.id, %{c: @long_value})

      assert search_key("test_fixtures_entity_module2", entity.id) == @long_value_folded
    end

    test "clears the search key when the attribute changes to a value that fits the sort key" do
      {:ok, entity} =
        %{c: @long_value}
        |> Module2.new()
        |> create()

      :ok = update(Module2, entity.id, %{c: "Łódź"})

      assert search_key("test_fixtures_entity_module2", entity.id) == nil
    end
  end
end
