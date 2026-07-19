defmodule Hologram.DatabaseTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Database

  alias Hologram.Database.Mapper
  alias Hologram.Reflection

  @insert_returning_id_sql ~s|INSERT INTO "hologram_data"."test_fixtures_entity_module1" ("id", "created_at", "updated_at") VALUES (gen_random_uuid(), now(), now()) RETURNING "id"|

  defp count_by_id(id) do
    count_sql =
      ~s|SELECT count(*) FROM "hologram_data"."test_fixtures_entity_module1" WHERE "id" = $1|

    {:ok, %Postgrex.Result{rows: [[count]]}} = query(count_sql, [id])
    count
  end

  describe "mapping/0" do
    test "returns the mapping derived from the discovered entity types" do
      assert mapping() == Mapper.derive!(Reflection.list_entities())
    end
  end

  describe "pool_name/0" do
    test "names a running connection pool that executes queries" do
      assert Postgrex.query!(pool_name(), "SELECT 1", []).rows == [[1]]
    end
  end

  describe "query/3" do
    test "executes the statement with the given params" do
      assert {:ok, %Postgrex.Result{rows: [[42]]}} = query("SELECT $1::int8 + 1", [41])
    end

    test "returns errors as tagged tuples" do
      assert {:error, %Postgrex.Error{}} = query("SELECT * FROM nonexistent_table")
    end
  end

  describe "rollback/1" do
    test "makes the enclosing transaction return the reason" do
      assert transaction(fn -> rollback(:some_reason) end) == {:error, :some_reason}
    end

    test "raises outside of a transaction" do
      assert_error ArgumentError, "cannot rollback - not inside a transaction", fn ->
        rollback(:some_reason)
      end
    end
  end

  describe "transaction/2" do
    test "commits on success and returns the function result" do
      {:ok, inserted_id} =
        transaction(fn ->
          {:ok, %Postgrex.Result{rows: [[id]]}} = query(@insert_returning_id_sql)
          id
        end)

      assert count_by_id(inserted_id) == 1

      delete_sql =
        ~s|DELETE FROM "hologram_data"."test_fixtures_entity_module1" WHERE "id" = $1|

      {:ok, _result} = query(delete_sql, [inserted_id])
    end

    test "joins the ongoing transaction when nested" do
      assert transaction(fn -> transaction(fn -> :inner end) end) == {:ok, {:ok, :inner}}
    end

    test "rollback in a joined transaction aborts the whole flat transaction" do
      result =
        transaction(fn ->
          {:ok, %Postgrex.Result{rows: [[id]]}} = query(@insert_returning_id_sql)
          Process.put(:inserted_id, id)
          transaction(fn -> rollback(:aborted) end)
        end)

      inserted_id = Process.get(:inserted_id)

      assert result == {:error, :aborted}
      assert count_by_id(inserted_id) == 0
    end

    test "rolls back and reraises on exceptions" do
      assert_error RuntimeError, "boom", fn ->
        transaction(fn ->
          {:ok, %Postgrex.Result{rows: [[id]]}} = query(@insert_returning_id_sql)
          Process.put(:inserted_id, id)
          raise RuntimeError, "boom"
        end)
      end

      assert count_by_id(Process.get(:inserted_id)) == 0
    end
  end
end
