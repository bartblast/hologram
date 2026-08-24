defmodule Hologram.DB.ConnectionTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.DB.Connection

  alias Hologram.DB.Config

  @insert_given_id_sql ~s|INSERT INTO "hologram_data"."test_fixtures_entity_module1" ("id", "created_at", "updated_at") VALUES ($1, now(), now())|

  @insert_returning_id_sql ~s|INSERT INTO "hologram_data"."test_fixtures_entity_module1" ("id", "created_at", "updated_at") VALUES (gen_random_uuid(), now(), now()) RETURNING "id"|

  defp count_by_id(id) do
    count_sql =
      ~s|SELECT count(*) FROM "hologram_data"."test_fixtures_entity_module1" WHERE "id" = $1|

    {:ok, %Postgrex.Result{rows: [[count]]}} = query(count_sql, [id])
    count
  end

  defp delete_by_id(id) do
    delete_sql = ~s|DELETE FROM "hologram_data"."test_fixtures_entity_module1" WHERE "id" = $1|

    {:ok, _result} = query(delete_sql, [id])
    :ok
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
    test "makes the innermost enclosing transaction return the reason" do
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

      delete_by_id(inserted_id)
    end

    test "keeps the enclosing transaction usable after a nested statement fails" do
      result =
        transaction(fn ->
          {:ok, %Postgrex.Result{rows: [[id]]}} = query(@insert_returning_id_sql)
          Process.put(:outer_id, id)

          transaction(fn ->
            {:error, %Postgrex.Error{}} = query(@insert_given_id_sql, [id])
            rollback(:refused)
          end)

          {:ok, _result} = query("SELECT 1")

          :usable
        end)

      outer_id = Process.get(:outer_id)

      assert result == {:ok, :usable}
      assert count_by_id(outer_id) == 1

      delete_by_id(outer_id)
    end

    # The probe runs one level down and its result travels out through rollback/1: a
    # savepoint that is gone cannot be released, and the refusal aborts the transaction
    # until the enclosing level rolls its own savepoint back.
    test "releases a nested transaction's savepoint when it raises" do
      result =
        transaction(fn ->
          transaction(fn ->
            Enum.each(1..3, fn _index ->
              try do
                transaction(fn -> raise RuntimeError, "boom" end)
              rescue
                _error in RuntimeError -> :ok
              end
            end)

            rollback(query("RELEASE SAVEPOINT hologram_3"))
          end)
        end)

      assert {:ok, {:error, {:error, %Postgrex.Error{postgres: %{code: code}}}}} = result
      assert code == :invalid_savepoint_specification
    end

    test "releases a nested transaction's savepoint when it rolls back" do
      result =
        transaction(fn ->
          transaction(fn ->
            Enum.each(1..3, fn _index -> transaction(fn -> rollback(:aborted) end) end)

            rollback(query("RELEASE SAVEPOINT hologram_3"))
          end)
        end)

      assert {:ok, {:error, {:error, %Postgrex.Error{postgres: %{code: code}}}}} = result
      assert code == :invalid_savepoint_specification
    end

    test "returns a nested transaction's result to the enclosing one" do
      assert transaction(fn -> transaction(fn -> :inner end) end) == {:ok, {:ok, :inner}}
    end

    test "rollback in a nested transaction aborts it alone and the enclosing one continues" do
      result =
        transaction(fn ->
          {:ok, %Postgrex.Result{rows: [[outer_id]]}} = query(@insert_returning_id_sql)
          Process.put(:outer_id, outer_id)

          nested_result =
            transaction(fn ->
              {:ok, %Postgrex.Result{rows: [[inner_id]]}} = query(@insert_returning_id_sql)
              Process.put(:inner_id, inner_id)
              rollback(:aborted)
            end)

          assert nested_result == {:error, :aborted}

          :continued
        end)

      outer_id = Process.get(:outer_id)

      assert result == {:ok, :continued}
      assert count_by_id(outer_id) == 1
      assert count_by_id(Process.get(:inner_id)) == 0

      delete_by_id(outer_id)
    end

    test "rolls each nesting level back on its own" do
      result =
        transaction(fn ->
          {:ok, %Postgrex.Result{rows: [[outer_id]]}} = query(@insert_returning_id_sql)
          Process.put(:outer_id, outer_id)

          transaction(fn ->
            {:ok, %Postgrex.Result{rows: [[middle_id]]}} = query(@insert_returning_id_sql)

            transaction(fn ->
              {:ok, %Postgrex.Result{rows: [[inner_id]]}} = query(@insert_returning_id_sql)
              Process.put(:inner_id, inner_id)
              rollback(:innermost)
            end)

            assert count_by_id(Process.get(:inner_id)) == 0
            assert count_by_id(middle_id) == 1

            Process.put(:middle_id, middle_id)
            rollback(:middle)
          end)

          assert count_by_id(Process.get(:middle_id)) == 0
          assert count_by_id(outer_id) == 1

          :continued
        end)

      outer_id = Process.get(:outer_id)

      assert result == {:ok, :continued}
      assert count_by_id(outer_id) == 1

      delete_by_id(outer_id)
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

  describe "with_timeout/2" do
    test "applies the timeout to queries that name none" do
      # A short timeout rather than the infinite one the migration paths use, so the effect
      # shows in a moment instead of after the driver's fifteen second default - and on a
      # connection of its own, because the pool answers a client that outstays its timeout
      # by dropping the connection, which on the shared pool would disturb every other test.
      {:ok, connection_pid} = Postgrex.start_link(Config.connection_opts())

      # The drop is logged as an error, which is expected here and alarming in a CI log
      # that cannot tell an intended timeout from a real outage.
      {result, _log} =
        ExUnit.CaptureLog.with_log(fn ->
          with_connection(connection_pid, fn ->
            with_timeout(50, fn -> query("SELECT pg_sleep(1)") end)
          end)
        end)

      GenServer.stop(connection_pid)

      assert {:error, error} = result

      # Which error arrives is the driver racing itself: it asks the server to cancel the
      # statement and drops the connection, so the answer is the cancellation when the
      # server replies first and a closed socket when it does not. Either way the timeout
      # fired - without it the query returns {:ok, _}, which is what makes this an assertion
      # about the timeout rather than about the driver's internals.
      assert error.__struct__ in [DBConnection.ConnectionError, Postgrex.Error]
    end

    test "leaves a query carrying its own timeout alone" do
      assert {:ok, %Postgrex.Result{}} =
               with_timeout(50, fn -> query("SELECT pg_sleep(1)", [], timeout: 5_000) end)
    end

    test "restores the enclosing default afterwards" do
      with_timeout(50, fn -> :ok end)

      assert {:ok, %Postgrex.Result{}} = query("SELECT pg_sleep(1)")
    end
  end

  describe "with_connection/2" do
    test "restores the enclosing connection when nested" do
      maintenance_opts = Config.connection_opts(database: "postgres")

      {:ok, outer_pid} = Postgrex.start_link(maintenance_opts)
      {:ok, inner_pid} = Postgrex.start_link(Config.connection_opts())

      after_nesting =
        with_connection(outer_pid, fn ->
          with_connection(inner_pid, fn -> :inner end)

          {:ok, %Postgrex.Result{rows: [[database]]}} = query("SELECT current_database()")

          database
        end)

      GenServer.stop(outer_pid)
      GenServer.stop(inner_pid)

      assert after_nesting == "postgres"
    end

    test "routes queries to the given connection and restores the pool afterwards" do
      database_opts =
        :hologram
        |> Application.get_env(:database, [])
        |> Config.resolve!(:test)

      {:ok, maintenance_pid} =
        Postgrex.start_link(
          database: "postgres",
          hostname: database_opts[:host],
          password: database_opts[:password],
          port: database_opts[:port],
          username: database_opts[:user]
        )

      current_database_sql = "SELECT current_database()"

      inside_result =
        with_connection(maintenance_pid, fn ->
          {:ok, %Postgrex.Result{rows: [[database]]}} = query(current_database_sql)
          database
        end)

      GenServer.stop(maintenance_pid)

      {:ok, %Postgrex.Result{rows: [[outside_database]]}} = query(current_database_sql)

      assert inside_result == "postgres"
      assert outside_database == database_opts[:database]
    end
  end
end
