defmodule Hologram.Database.PrimitivesTest do
  # TODO: once Hologram.Database delegates its entity row operations to a dedicated
  # internal module, align this file with that module so that every test file matches
  # a module file.
  use Hologram.Test.DatabaseCase, async: true

  import Hologram.Database

  alias Hologram.Database.Codec
  alias Hologram.Entity
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module4

  describe "create/1" do
    test "inserts a full row and stamps both timestamps with the same value" do
      entity = Entity.new(Module2, a: true, c: "some text")

      created_entity = create(entity)

      assert %DateTime{} = created_entity.created_at
      assert created_entity.updated_at == created_entity.created_at

      select_sql =
        ~s|SELECT "a", "b", "c" FROM "hologram_data"."test_fixtures_entity_module2" WHERE "id" = $1|

      encoded_id = Codec.encode(created_entity.id, :uuid)

      assert {:ok, %Postgrex.Result{rows: [[true, nil, "some text"]]}} =
               query(select_sql, [encoded_id])
    end

    test "encodes attribute values per type at the driver boundary" do
      written_at = DateTime.utc_now(:microsecond)

      entity = Entity.new(Module4, a: ~D[2026-07-19], b: written_at, d: 1.5)

      created_entity = create(entity)

      select_sql =
        ~s|SELECT "a", "b", "c", "d" FROM "hologram_data"."test_fixtures_entity_module4" WHERE "id" = $1|

      encoded_id = Codec.encode(created_entity.id, :uuid)

      assert {:ok, %Postgrex.Result{rows: [[~D[2026-07-19], ^written_at, "x", 1.5]]}} =
               query(select_sql, [encoded_id])
    end

    test "writes to-one relationship references into the reference columns" do
      target_entity = create(Entity.new(Module1))

      entity = Entity.new(Module3, c: target_entity.id)

      created_entity = create(entity)

      select_sql =
        ~s|SELECT "b_id", "c_id" FROM "hologram_data"."test_fixtures_entity_module3" WHERE "id" = $1|

      encoded_id = Codec.encode(created_entity.id, :uuid)
      encoded_target_id = Codec.encode(target_entity.id, :uuid)

      assert {:ok, %Postgrex.Result{rows: [[nil, ^encoded_target_id]]}} =
               query(select_sql, [encoded_id])
    end

    test "raises on constraint violations" do
      entity = Entity.new(Module1)
      create(entity)

      error =
        try do
          create(entity)
        rescue
          error in Postgrex.Error -> error
        end

      assert error.postgres.code == :unique_violation
    end
  end
end
