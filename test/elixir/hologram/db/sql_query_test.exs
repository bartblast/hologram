defmodule Hologram.DB.SQLQueryTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.DB.SQLQuery

  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.Entity
  alias Hologram.SQLError

  # Reaches the server outside the sandbox: the path without an enclosing transaction opens a
  # transaction of its own, which the sandbox would turn into a savepoint.
  @moduletag :database

  @count_by_id_sql ~s|SELECT count(*) AS "count" FROM "hologram_data"."test_fixtures_entity_module1" WHERE "id" = $1|

  @delete_by_id_sql ~s|DELETE FROM "hologram_data"."test_fixtures_entity_module1" WHERE "id" = $1|

  @insert_given_id_sql ~s|INSERT INTO "hologram_data"."test_fixtures_entity_module1" ("id", "created_at", "updated_at", "$revisions") VALUES ($1, now(), now(), '{}')|

  @insert_returning_id_sql ~s|INSERT INTO "hologram_data"."test_fixtures_entity_module1" ("id", "created_at", "updated_at", "$revisions") VALUES (gen_random_uuid(), now(), now(), '{}') RETURNING "id"|

  @lock_by_id_sql ~s|SELECT "id" FROM "hologram_data"."test_fixtures_entity_module1" WHERE "id" = $1 FOR UPDATE|

  @remove_by_id_in_cte_sql ~s|WITH removed AS (DELETE FROM "hologram_data"."test_fixtures_entity_module1" WHERE "id" = $1 RETURNING "id") SELECT count(*) AS "count" FROM removed|

  defp count_by_id(id) do
    {:ok, %Postgrex.Result{rows: [[count]]}} = Connection.query(@count_by_id_sql, [id])
    count
  end

  defp delete_by_id(id) do
    {:ok, _result} = Connection.query(@delete_by_id_sql, [id])
    :ok
  end

  defp insert_row do
    {:ok, %Postgrex.Result{rows: [[id]]}} = Connection.query(@insert_returning_id_sql)
    id
  end

  defp read_only_message(server_message) do
    "DB.sql/3 can only read data, and this statement writes it (PostgreSQL: #{server_message}). " <>
      "Use DB.create/1, DB.update/3 or DB.delete/2 to write, so that the change reaches the sync " <>
      "and the clients."
  end

  describe "run/3" do
    test "returns the columns and rows of a select with params" do
      assert run(~s|SELECT $1::int8 + 1 AS "sum"|, [41], []) ==
               {:ok, %{columns: ["sum"], rows: [[42]]}}
    end

    test "returns empty columns and rows for a statement with no result set" do
      assert run("SET LOCAL statement_timeout = '5s'", [], []) == {:ok, %{columns: [], rows: []}}
    end

    test "sees the enclosing transaction's uncommitted rows" do
      result =
        Connection.transaction(fn ->
          id = insert_row()

          assert run(@count_by_id_sql, [id], []) == {:ok, %{columns: ["count"], rows: [[1]]}}

          Connection.rollback(:done)
        end)

      assert result == {:error, :done}
    end

    test "leaves the enclosing transaction writable" do
      {:ok, id} =
        Connection.transaction(fn ->
          {:ok, _result} = run(~s|SELECT 1 AS "one"|, [], [])
          insert_row()
        end)

      assert count_by_id(id) == 1

      delete_by_id(id)
    end

    test "leaves the enclosing transaction usable after a refused write" do
      {:ok, id} =
        Connection.transaction(fn ->
          assert {:error, %SQLError{code: :read_only_sql_transaction}} =
                   run(@insert_returning_id_sql, [], [])

          insert_row()
        end)

      assert count_by_id(id) == 1

      delete_by_id(id)
    end

    test "leaves the enclosing transaction usable after a statement error" do
      {:ok, id} =
        Connection.transaction(fn ->
          assert {:error, %SQLError{code: :undefined_table}} =
                   run("SELECT * FROM nonexistent_table", [], [])

          insert_row()
        end)

      assert count_by_id(id) == 1

      delete_by_id(id)
    end

    test "refuses an insert with Hologram's message" do
      id = Codec.encode(Entity.generate_id(), :uuid)

      assert run(@insert_given_id_sql, [id], []) ==
               {:error,
                %SQLError{
                  code: :read_only_sql_transaction,
                  message: read_only_message("cannot execute INSERT in a read-only transaction")
                }}

      assert count_by_id(id) == 0
    end

    # A check on the statement's first word would let this one through: the write sits inside
    # the CTE of a SELECT, and PostgreSQL's message names the SELECT.
    test "refuses a write hidden in a CTE" do
      id = insert_row()

      assert run(@remove_by_id_in_cte_sql, [id], []) ==
               {:error,
                %SQLError{
                  code: :read_only_sql_transaction,
                  message: read_only_message("cannot execute SELECT in a read-only transaction")
                }}

      assert count_by_id(id) == 1

      delete_by_id(id)
    end

    test "refuses a row lock" do
      id = insert_row()

      assert run(@lock_by_id_sql, [id], []) ==
               {:error,
                %SQLError{
                  code: :read_only_sql_transaction,
                  message:
                    read_only_message(
                      "cannot execute SELECT FOR UPDATE in a read-only transaction"
                    )
                }}

      delete_by_id(id)
    end

    test "returns a statement error with the server's message" do
      assert run("SELECT * FROM nonexistent_table", [], []) ==
               {:error,
                %SQLError{
                  code: :undefined_table,
                  message: ~s(relation "nonexistent_table" does not exist)
                }}
    end
  end
end
