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

  @id "0192f3a0-7b1e-7c2d-9a4b-1f2e3d4c5b6a"

  @insert_given_id_sql ~s|INSERT INTO "hologram_data"."test_fixtures_entity_module1" ("id", "created_at", "updated_at", "$revisions") VALUES ($1, now(), now(), '{}')|

  @insert_returning_id_sql ~s|INSERT INTO "hologram_data"."test_fixtures_entity_module1" ("id", "created_at", "updated_at", "$revisions") VALUES (gen_random_uuid(), now(), now(), '{}') RETURNING "id"|

  @lock_by_id_sql ~s|SELECT "id" FROM "hologram_data"."test_fixtures_entity_module1" WHERE "id" = $1 FOR UPDATE|

  @other_id "0192f3a0-7b1e-7c2d-9a4b-1f2e3d4c5b6b"

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

    test "decodes a uuid column to the canonical id string" do
      assert run(~s|SELECT '#{@id}'::uuid AS "id"|, [], []) ==
               {:ok, %{columns: ["id"], rows: [[@id]]}}
    end

    test "decodes the elements of a uuid array column" do
      assert run(~s|SELECT ARRAY['#{@id}'::uuid, NULL, '#{@other_id}'::uuid] AS "ids"|, [], []) ==
               {:ok, %{columns: ["ids"], rows: [[[@id, nil, @other_id]]]}}
    end

    test "decodes the elements of a multidimensional uuid array column" do
      statement = ~s|SELECT ARRAY[['#{@id}'::uuid], ['#{@other_id}'::uuid]] AS "ids"|

      assert run(statement, [], []) == {:ok, %{columns: ["ids"], rows: [[[[@id], [@other_id]]]]}}
    end

    test "decodes a null uuid column as nil" do
      assert run(~s|SELECT NULL::uuid AS "id"|, [], []) ==
               {:ok, %{columns: ["id"], rows: [[nil]]}}
    end

    # The conversion goes by the column's type, so 16 bytes that would decode as a uuid stay bytes.
    test "leaves a 16-byte bytea column as a binary" do
      bytes = Codec.encode(@id, :uuid)

      assert run(~s|SELECT $1::bytea AS "bytes"|, [bytes], []) ==
               {:ok, %{columns: ["bytes"], rows: [[bytes]]}}
    end

    test "leaves a uuid-shaped text param and column as text" do
      assert run(~s|SELECT $1::text AS "id"|, [@id], []) ==
               {:ok, %{columns: ["id"], rows: [[@id]]}}
    end

    test "encodes a canonical id string for a uuid param" do
      assert run(~s|SELECT $1::uuid = '#{@id}'::uuid AS "same"|, [@id], []) ==
               {:ok, %{columns: ["same"], rows: [[true]]}}
    end

    test "encodes the elements of a uuid array param" do
      assert run(~s|SELECT $1::uuid[] AS "ids"|, [[@id, nil, @other_id]], []) ==
               {:ok, %{columns: ["ids"], rows: [[[@id, nil, @other_id]]]}}
    end

    test "encodes the elements of a multidimensional uuid array param" do
      assert run(~s|SELECT $1::uuid[] AS "ids"|, [[[@id], [@other_id]]], []) ==
               {:ok, %{columns: ["ids"], rows: [[[[@id], [@other_id]]]]}}
    end

    test "passes a 16-byte binary for a uuid param through" do
      assert run(~s|SELECT $1::uuid AS "id"|, [Codec.encode(@id, :uuid)], []) ==
               {:ok, %{columns: ["id"], rows: [[@id]]}}
    end

    test "passes a nil uuid param through" do
      assert run(~s|SELECT $1::uuid AS "id"|, [nil], []) ==
               {:ok, %{columns: ["id"], rows: [[nil]]}}
    end

    test "runs the statement under a fifteen-second timeout by default" do
      assert run(~s|SELECT current_setting('statement_timeout') AS "timeout"|, [], []) ==
               {:ok, %{columns: ["timeout"], rows: [["15s"]]}}
    end

    test "runs the statement under the given timeout" do
      assert run(~s|SELECT current_setting('statement_timeout') AS "timeout"|, [],
               timeout: 60_000
             ) ==
               {:ok, %{columns: ["timeout"], rows: [["1min"]]}}
    end

    test "runs the statement with no timeout for :infinity" do
      assert run(~s|SELECT current_setting('statement_timeout') AS "timeout"|, [],
               timeout: :infinity
             ) ==
               {:ok, %{columns: ["timeout"], rows: [["0"]]}}
    end

    # A driver deadline on the transaction the read opens would close the connection when it fires,
    # so the statement timeout is the one bound. The calling process's default driver timeout is
    # shorter than the statement here, and the read still answers.
    test "runs past the calling process's driver timeout" do
      result = Connection.with_timeout(50, fn -> run("SELECT pg_sleep(0.2)", [], []) end)

      assert result == {:ok, %{columns: ["pg_sleep"], rows: [[:void]]}}
    end

    test "leaves the enclosing transaction's statement timeout as it was" do
      result =
        Connection.transaction(fn ->
          statement = "SELECT current_setting('statement_timeout')"

          {:ok, %Postgrex.Result{rows: [[timeout_before]]}} = Connection.query(statement)
          {:error, %SQLError{code: :query_canceled}} = run("SELECT pg_sleep(1)", [], timeout: 50)
          {:ok, %Postgrex.Result{rows: [[timeout_after]]}} = Connection.query(statement)

          Connection.rollback({timeout_before, timeout_after})
        end)

      assert {:error, {timeout, timeout}} = result
    end

    test "leaves the enclosing transaction usable after a cancelled statement" do
      {:ok, id} =
        Connection.transaction(fn ->
          assert {:error, %SQLError{code: :query_canceled}} =
                   run("SELECT pg_sleep(1)", [], timeout: 50)

          insert_row()
        end)

      assert count_by_id(id) == 1

      delete_by_id(id)
    end

    test "leaves the enclosing transaction usable after a param that does not fit" do
      {:ok, id} =
        Connection.transaction(fn ->
          assert_error ArgumentError,
                       "DB.sql/3 got 0 params for a statement with 1 placeholder",
                       fn -> run(~s|SELECT $1::uuid AS "id"|, [], []) end

          insert_row()
        end)

      assert count_by_id(id) == 1

      delete_by_id(id)
    end

    test "leaves the enclosing transaction usable after a param of another type" do
      expected_msg =
        "a param of DB.sql/3 does not fit the type of its placeholder in the statement - " <>
          ~s(Postgrex expected an integer in -9223372036854775808..9223372036854775807, got ) <>
          ~s("x". Please make sure the value you are passing matches the definition in your ) <>
          "table or in your query or convert the value accordingly."

      {:ok, id} =
        Connection.transaction(fn ->
          assert_error ArgumentError, expected_msg, fn ->
            run(~s|SELECT $1::int8 AS "n"|, ["x"], [])
          end

          insert_row()
        end)

      assert count_by_id(id) == 1

      delete_by_id(id)
    end

    # A transaction-level lock ends with the transaction the read runs in, so it outlives nothing.
    test "allows a transaction-level advisory lock" do
      assert run("SELECT pg_advisory_xact_lock(1378)", [], []) ==
               {:ok, %{columns: ["pg_advisory_xact_lock"], rows: [[:void]]}}
    end

    test "allows a lock function name inside a param" do
      assert run(~s|SELECT $1::text AS "text"|, ["pg_advisory_lock(1378)"], []) ==
               {:ok, %{columns: ["text"], rows: [["pg_advisory_lock(1378)"]]}}
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

    test "cancels a statement past its timeout" do
      assert run("SELECT pg_sleep(1)", [], timeout: 50) ==
               {:error,
                %SQLError{
                  code: :query_canceled,
                  message: "canceling statement due to statement timeout"
                }}
    end

    test "raises on fewer params than placeholders" do
      assert_error ArgumentError,
                   "DB.sql/3 got 0 params for a statement with 1 placeholder",
                   fn ->
                     run(~s|SELECT $1::uuid AS "id"|, [], [])
                   end
    end

    test "raises on more params than placeholders" do
      assert_error ArgumentError,
                   "DB.sql/3 got 3 params for a statement with 2 placeholders",
                   fn ->
                     run(~s|SELECT $1::uuid AS "a", $2::uuid AS "b"|, [@id, @other_id, @id], [])
                   end
    end

    test "raises on a string that is not a canonical id for a uuid param" do
      expected_msg =
        "a param of DB.sql/3 does not fit the type of its placeholder in the statement - " <>
          ~s(Postgrex expected a binary of 16 bytes, got "not-an-id". Please make sure the ) <>
          "value you are passing matches the definition in your table or in your query or " <>
          "convert the value accordingly."

      assert_error ArgumentError, expected_msg, fn ->
        run(~s|SELECT $1::uuid AS "id"|, ["not-an-id"], [])
      end
    end

    test "raises on a param of another type than its placeholder" do
      expected_msg =
        "a param of DB.sql/3 does not fit the type of its placeholder in the statement - " <>
          ~s(Postgrex expected an integer in -9223372036854775808..9223372036854775807, got ) <>
          ~s("x". Please make sure the value you are passing matches the definition in your ) <>
          "table or in your query or convert the value accordingly."

      assert_error ArgumentError, expected_msg, fn ->
        run(~s|SELECT $1::int8 AS "n"|, ["x"], [])
      end
    end

    test "raises on an unknown option" do
      assert_error ArgumentError,
                   "unknown option :timeot for DB.sql/3 - the one option is :timeout",
                   fn -> run(~s|SELECT 1 AS "one"|, [], timeot: 5_000) end
    end

    # PostgreSQL reads a zero statement timeout as no limit.
    test "raises on a zero timeout" do
      assert_error ArgumentError,
                   "invalid timeout 0 for DB.sql/3 - give a positive number of milliseconds or :infinity",
                   fn -> run(~s|SELECT 1 AS "one"|, [], timeout: 0) end
    end

    test "raises on a timeout that is not an integer" do
      assert_error ArgumentError,
                   ~s(invalid timeout "5s" for DB.sql/3 - give a positive number of milliseconds or :infinity),
                   fn -> run(~s|SELECT 1 AS "one"|, [], timeout: "5s") end
    end

    # A session-level lock outlives the rolled-back read and stays with whichever pooled connection
    # ran it, where the next read cannot release it.
    test "raises on a session-level advisory lock" do
      expected_msg =
        "DB.sql/3 cannot take a session-level advisory lock - it would stay with a pooled " <>
          "connection after the read. Take pg_advisory_xact_lock inside DB.transaction/2 instead."

      assert_error ArgumentError, expected_msg, fn ->
        run("SELECT pg_advisory_lock(1378)", [], [])
      end
    end

    test "raises on a shared session-level advisory lock taken with try, in any case" do
      expected_msg =
        "DB.sql/3 cannot take a session-level advisory lock - it would stay with a pooled " <>
          "connection after the read. Take pg_advisory_xact_lock inside DB.transaction/2 instead."

      assert_error ArgumentError, expected_msg, fn ->
        run("SELECT PG_TRY_ADVISORY_LOCK_SHARED(1378)", [], [])
      end
    end

    test "raises on a named prepared statement behind a comment" do
      expected_msg =
        "DB.sql/3 cannot prepare a named statement - it would stay with a pooled connection " <>
          "after the read. Pass the statement to DB.sql/3 itself, with its params."

      assert_error ArgumentError, expected_msg, fn ->
        run("-- the monthly report\nPREPARE report AS SELECT 1", [], [])
      end
    end
  end
end
