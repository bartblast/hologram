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

  defp count_edges(source_entity, target_entity) do
    count_sql =
      ~s|SELECT count(*) FROM "hologram_data"."test_fixtures_entity_module3_a_$join" WHERE "source_id" = $1 AND "target_id" = $2|

    encoded_source_id = Codec.encode(source_entity.id, :uuid)
    encoded_target_id = Codec.encode(target_entity.id, :uuid)

    {:ok, %Postgrex.Result{rows: [[count]]}} =
      query(count_sql, [encoded_source_id, encoded_target_id])

    count
  end

  describe "add_relationship/4" do
    test "adds an edge to the join table" do
      required_target = create(Entity.new(Module1))
      source_entity = create(Entity.new(Module3, c: required_target.id))
      target_entity = create(Entity.new(Module2, a: true, c: "some text"))

      assert add_relationship(Module3, source_entity.id, :a, target_entity.id) == :ok

      assert count_edges(source_entity, target_entity) == 1
    end

    test "is idempotent" do
      required_target = create(Entity.new(Module1))
      source_entity = create(Entity.new(Module3, c: required_target.id))
      target_entity = create(Entity.new(Module2, a: true, c: "some text"))

      :ok = add_relationship(Module3, source_entity.id, :a, target_entity.id)
      :ok = add_relationship(Module3, source_entity.id, :a, target_entity.id)

      assert count_edges(source_entity, target_entity) == 1
    end

    test "raises when the relationship is not a declared to-many relationship" do
      expected_msg =
        "invalid relationship for Hologram.Test.Fixtures.Entity.Module3 - :b is not a declared to-many relationship"

      assert_error ArgumentError, expected_msg, fn ->
        add_relationship(Module3, Entity.generate_id(), :b, Entity.generate_id())
      end
    end

    test "raises when the source or target entity is missing" do
      required_target = create(Entity.new(Module1))
      source_entity = create(Entity.new(Module3, c: required_target.id))

      error =
        try do
          add_relationship(Module3, source_entity.id, :a, Entity.generate_id())
        rescue
          error in Postgrex.Error -> error
        end

      assert error.postgres.code == :foreign_key_violation
    end
  end

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

  describe "get/2" do
    test "returns the entity with values decoded back into their logical types" do
      entity = Entity.new(Module4, a: ~D[2026-07-19], b: DateTime.utc_now(:microsecond), d: 1.5)

      created_entity = create(entity)

      assert get(Module4, created_entity.id) == created_entity
    end

    test "returns to-one relationship references as target ids" do
      target_entity = create(Entity.new(Module1))
      created_entity = create(Entity.new(Module3, c: target_entity.id))

      assert get(Module3, created_entity.id) == created_entity
    end

    test "returns nil when no row matches" do
      assert get(Module1, Entity.generate_id()) == nil
    end
  end

  describe "update/3" do
    test "sets exactly the changed columns and bumps updated_at" do
      created_entity = create(Entity.new(Module2, a: true, b: 1, c: "before"))

      assert update(Module2, created_entity.id, %{c: "after"}) == :ok

      reloaded_entity = get(Module2, created_entity.id)

      assert reloaded_entity.c == "after"
      assert reloaded_entity.a == created_entity.a
      assert reloaded_entity.b == created_entity.b
      assert reloaded_entity.created_at == created_entity.created_at
      assert DateTime.compare(reloaded_entity.updated_at, created_entity.updated_at) == :gt
    end

    test "sets, reassigns and clears to-one references" do
      first_target = create(Entity.new(Module1))
      second_target = create(Entity.new(Module1))
      optional_target = create(Entity.new(Module2, a: true, c: "some text"))

      created_entity = create(Entity.new(Module3, c: first_target.id))

      :ok = update(Module3, created_entity.id, %{c: second_target.id})
      assert get(Module3, created_entity.id).c == second_target.id

      :ok = update(Module3, created_entity.id, %{b: optional_target.id})
      assert get(Module3, created_entity.id).b == optional_target.id

      :ok = update(Module3, created_entity.id, %{b: nil})
      assert get(Module3, created_entity.id).b == nil
    end

    test "raises when changes name anything but declared attributes and to-one relationships" do
      created_entity = create(Entity.new(Module2, a: true, c: "some text"))

      expected_unknown_msg =
        "invalid changes for Hologram.Test.Fixtures.Entity.Module2 - only declared attributes and to-one relationships can be updated: :nonexistent"

      assert_error ArgumentError, expected_unknown_msg, fn ->
        update(Module2, created_entity.id, %{nonexistent: 1})
      end

      expected_system_msg =
        "invalid changes for Hologram.Test.Fixtures.Entity.Module2 - only declared attributes and to-one relationships can be updated: :created_at"

      assert_error ArgumentError, expected_system_msg, fn ->
        update(Module2, created_entity.id, %{created_at: DateTime.utc_now(:microsecond)})
      end
    end

    test "raises when the id names no entity" do
      nonexistent_id = Entity.generate_id()

      expected_msg =
        "cannot update Hologram.Test.Fixtures.Entity.Module2 - no entity with id #{inspect(nonexistent_id)}"

      assert_error ArgumentError, expected_msg, fn ->
        update(Module2, nonexistent_id, %{c: "some text"})
      end
    end
  end
end
