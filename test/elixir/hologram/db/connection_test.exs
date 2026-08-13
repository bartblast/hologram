defmodule Hologram.DB.ConnectionTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.DB.Connection

  alias Hologram.DB.Config

  @insert_returning_id_sql ~s|INSERT INTO "hologram_data"."test_fixtures_entity_module1" ("id", "created_at", "updated_at") VALUES (gen_random_uuid(), now(), now()) RETURNING "id"|

  defp count_by_id(id) do
    count_sql =
      ~s|SELECT count(*) FROM "hologram_data"."test_fixtures_entity_module1" WHERE "id" = $1|

    {:ok, %Postgrex.Result{rows: [[count]]}} = query(count_sql, [id])
    count
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
