defmodule Hologram.DB.ResetTest do
  use Hologram.Test.ScratchDatabaseCase, async: true

  import ExUnit.CaptureLog
  import Hologram.DB.Reset

  alias Hologram.DB.Config
  alias Hologram.DB.Mapper
  alias Hologram.DB.SchemaReconciler

  @claim %{
    otp_app: "hologram",
    env: "dev",
    hologram_version: "0.5.0",
    timestamp: ~U[2026-11-24 12:00:00.000000Z]
  }

  # The suite's server, pointed at the test's own scratch database.
  setup %{scratch_opts: scratch_opts} do
    database_opts =
      :hologram
      |> Application.get_env(:database, [])
      |> Keyword.put(:database, scratch_opts[:database])
      |> Config.resolve!(:test)

    [database_opts: database_opts]
  end

  # Also writes a row into a Hologram table, which a refused reset has to leave in place.
  defp claim(scratch, context \\ @claim) do
    route(scratch, fn -> SchemaReconciler.ensure_managed!(context) end)
    query!(scratch, ~s[CREATE TABLE "hologram_data"."post" ("id" integer PRIMARY KEY)])
    query!(scratch, ~s[INSERT INTO "hologram_data"."post" VALUES (7)])
  end

  defp count_client_sessions(scratch_opts) do
    with_maintenance(scratch_opts, fn maintenance ->
      %{rows: [[count]]} =
        Postgrex.query!(
          maintenance,
          """
          SELECT count(*) FROM pg_catalog.pg_stat_activity
          WHERE "datname" = $1 AND "backend_type" = 'client backend'
          """,
          [scratch_opts[:database]]
        )

      count
    end)
  end

  defp database_exists?(scratch_opts) do
    with_maintenance(scratch_opts, fn maintenance ->
      %{rows: rows} =
        Postgrex.query!(
          maintenance,
          ~s(SELECT 1 FROM pg_catalog.pg_database WHERE "datname" = $1),
          [scratch_opts[:database]]
        )

      rows != []
    end)
  end

  # The reset refuses while another client is connected, and the case template's pool is one, so
  # each test builds the database's state through it and then stops it. A closed session leaves
  # pg_stat_activity a moment after its socket does. The mark goes first: a marked database with
  # no session is one another run's bootstrap drops. A run killed after that leaves the database
  # unmarked, for the test env reset to drop by its scratch name.
  defp disconnect(scratch_opts) do
    with_scratch(scratch_opts, fn connection ->
      query!(
        connection,
        "COMMENT ON DATABASE #{Mapper.quote_identifier(scratch_opts[:database])} IS NULL"
      )
    end)

    stop_supervised!(DBConnection.ConnectionPool)
    wait_until(fn -> count_client_sessions(scratch_opts) == 0 end)
  end

  defp drop_scratch_database(scratch_opts) do
    disconnect(scratch_opts)

    with_maintenance(scratch_opts, fn maintenance ->
      Postgrex.query!(
        maintenance,
        "DROP DATABASE #{Mapper.quote_identifier(scratch_opts[:database])}",
        []
      )
    end)
  end

  defp hologram_schemas(scratch_opts) do
    with_scratch(scratch_opts, fn connection ->
      %{rows: rows} =
        Postgrex.query!(
          connection,
          """
          SELECT "nspname" FROM pg_catalog.pg_namespace
          WHERE "nspname" IN ('hologram_data', 'hologram_system') ORDER BY "nspname"
          """,
          []
        )

      Enum.map(rows, fn [name] -> name end)
    end)
  end

  defp other_table_rows(scratch_opts) do
    with_scratch(scratch_opts, fn connection ->
      %{rows: rows} = Postgrex.query!(connection, ~s(SELECT "id" FROM "public"."kept"), [])
      rows
    end)
  end

  defp post_rows(scratch_opts) do
    with_scratch(scratch_opts, fn connection ->
      %{rows: rows} = Postgrex.query!(connection, ~s(SELECT "id" FROM "hologram_data"."post"), [])
      rows
    end)
  end

  defp query!(scratch, statement) do
    Postgrex.query!(scratch, statement, [])
  end

  defp with_maintenance(scratch_opts, fun) do
    scratch_opts
    |> Keyword.put(:database, "postgres")
    |> with_session(fun)
  end

  defp with_scratch(scratch_opts, fun), do: with_session(scratch_opts, fun)

  defp with_session(opts, fun) do
    {:ok, connection} =
      opts
      |> Keyword.put(:pool_size, 1)
      |> Postgrex.start_link()

    try do
      fun.(connection)
    after
      GenServer.stop(connection)
    end
  end

  describe "reset!/3" do
    test "creates a missing database", %{database_opts: database_opts, scratch_opts: scratch_opts} do
      drop_scratch_database(scratch_opts)

      assert reset!(database_opts, :hologram, :dev) == :created

      assert database_exists?(scratch_opts)
      assert hologram_schemas(scratch_opts) == []
    end

    test "drops the Hologram schemas of a database this app and env manage, keeping the rest", %{
      database_opts: database_opts,
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      claim(scratch)
      query!(scratch, ~s[CREATE TABLE "public"."kept" ("id" integer)])
      query!(scratch, ~s[INSERT INTO "public"."kept" VALUES (1)])
      disconnect(scratch_opts)

      assert reset!(database_opts, :hologram, :dev) == :dropped

      assert hologram_schemas(scratch_opts) == []
      assert other_table_rows(scratch_opts) == [[1]]
    end

    test "finds nothing to drop in a database with no Hologram schemas", %{
      database_opts: database_opts,
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      query!(scratch, ~s[CREATE TABLE "public"."kept" ("id" integer)])
      query!(scratch, ~s[INSERT INTO "public"."kept" VALUES (1)])
      disconnect(scratch_opts)

      assert reset!(database_opts, :hologram, :dev) == :empty

      assert other_table_rows(scratch_opts) == [[1]]
    end

    test "drops Hologram schemas that have no marker table", %{
      database_opts: database_opts,
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      query!(scratch, ~s(CREATE SCHEMA "hologram_data"))
      query!(scratch, ~s[CREATE TABLE "hologram_data"."post" ("id" integer)])
      disconnect(scratch_opts)

      assert reset!(database_opts, :hologram, :dev) == :dropped

      assert hologram_schemas(scratch_opts) == []
    end

    test "drops Hologram schemas whose marker table is empty", %{
      database_opts: database_opts,
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      claim(scratch)
      query!(scratch, ~s(DELETE FROM "hologram_system"."database"))
      disconnect(scratch_opts)

      assert reset!(database_opts, :hologram, :dev) == :dropped

      assert hologram_schemas(scratch_opts) == []
    end

    test "drops the schemas of a marker table from another system table layout", %{
      database_opts: database_opts,
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      query!(scratch, ~s(CREATE SCHEMA "hologram_data"))
      query!(scratch, ~s(CREATE SCHEMA "hologram_system"))

      query!(scratch, """
      CREATE TABLE "hologram_system"."database" (
        "otp_app" text, "env" text, "managed_by" text, "layout_of_the_future" bigint
      )
      """)

      query!(scratch, """
      INSERT INTO "hologram_system"."database" VALUES ('hologram', 'dev', 'reconciliation', 99)
      """)

      disconnect(scratch_opts)

      assert reset!(database_opts, :hologram, :dev) == :dropped

      assert hologram_schemas(scratch_opts) == []
    end

    test "refuses another app's database, changing nothing", %{
      database_opts: database_opts,
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      claim(scratch, %{@claim | otp_app: "other_app"})
      disconnect(scratch_opts)

      message =
        ~s(database "#{scratch_opts[:database]}" belongs to app "other_app" - the current app is "hologram" - the reset leaves another app's database alone, point the config at the right database)

      assert_raise RuntimeError, message, fn -> reset!(database_opts, :hologram, :dev) end

      assert post_rows(scratch_opts) == [[7]]
    end

    test "refuses another env's database, changing nothing", %{
      database_opts: database_opts,
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      claim(scratch, %{@claim | env: "prod"})
      disconnect(scratch_opts)

      message =
        ~s(database "#{scratch_opts[:database]}" belongs to the "prod" env - the current env is "dev" - the reset leaves another env's database alone, point the config at the right database)

      assert_raise RuntimeError, message, fn -> reset!(database_opts, :hologram, :dev) end

      assert post_rows(scratch_opts) == [[7]]
    end

    test "refuses a database its migrations build, changing nothing", %{
      database_opts: database_opts,
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      claim(scratch)
      query!(scratch, ~s(UPDATE "hologram_system"."database" SET "managed_by" = 'migrations'))
      disconnect(scratch_opts)

      message =
        ~s(database "#{scratch_opts[:database]}" is managed by migrations - the reset clears only a database schema reconciliation manages)

      assert_raise RuntimeError, message, fn -> reset!(database_opts, :hologram, :dev) end

      assert post_rows(scratch_opts) == [[7]]
    end

    test "refuses while another client is connected, changing nothing", %{
      database_opts: database_opts,
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      claim(scratch)
      disconnect(scratch_opts)

      with_scratch(scratch_opts, fn connection ->
        query!(connection, "SELECT 1")

        message =
          ~s(1 other session is connected to database "#{scratch_opts[:database]}" - stop the app and close every other client of it, like psql, then run the reset again)

        assert_raise RuntimeError, message, fn -> reset!(database_opts, :hologram, :dev) end
      end)

      assert post_rows(scratch_opts) == [[7]]
    end

    test "counts every other client connected", %{
      database_opts: database_opts,
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      query!(scratch, "SELECT 1")
      disconnect(scratch_opts)

      with_scratch(scratch_opts, fn first ->
        with_scratch(scratch_opts, fn second ->
          query!(first, "SELECT 1")
          query!(second, "SELECT 1")

          assert_raise RuntimeError, ~r/^2 other sessions are connected/, fn ->
            reset!(database_opts, :hologram, :dev)
          end
        end)
      end)
    end

    test "says how many sessions its user can't see the kind of", %{
      database_opts: database_opts,
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      role = scratch_opts[:database] <> "_role"
      quoted_role = Mapper.quote_identifier(role)

      with_maintenance(scratch_opts, fn maintenance ->
        query!(maintenance, "CREATE ROLE #{quoted_role} LOGIN PASSWORD 'scratch'")
      end)

      on_exit(fn ->
        with_maintenance(scratch_opts, fn maintenance ->
          query!(maintenance, "DROP ROLE IF EXISTS #{quoted_role}")
        end)
      end)

      query!(scratch, "SELECT 1")
      disconnect(scratch_opts)

      with_scratch(scratch_opts, fn connection ->
        query!(connection, "SELECT 1")

        message =
          ~s(1 other session is connected to database "#{scratch_opts[:database]}" - stop the app and close every other client of it, like psql, then run the reset again - user "#{role}" can't see what 1 of them is, and a background worker counts too then - a superuser running GRANT pg_read_all_stats TO #{quoted_role} lets the reset tell)

        assert_raise RuntimeError, message, fn ->
          reset!([{:user, role}, {:password, "scratch"} | database_opts], :hologram, :dev)
        end
      end)
    end

    test "refuses a database with more than one marker row, changing nothing", %{
      database_opts: database_opts,
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      claim(scratch)

      query!(
        scratch,
        ~s(INSERT INTO "hologram_system"."database" SELECT * FROM "hologram_system"."database")
      )

      disconnect(scratch_opts)

      message =
        ~s(database "#{scratch_opts[:database]}" has more than one Hologram marker row - the reset can't tell whose database it is)

      assert_raise RuntimeError, message, fn -> reset!(database_opts, :hologram, :dev) end

      assert post_rows(scratch_opts) == [[7]]
    end

    test "refuses when a foreign key outside the Hologram schemas references them, changing nothing",
         %{database_opts: database_opts, scratch: scratch, scratch_opts: scratch_opts} do
      claim(scratch)

      query!(
        scratch,
        ~s[CREATE TABLE "public"."payment" ("post_id" integer REFERENCES "hologram_data"."post")]
      )

      disconnect(scratch_opts)

      message =
        ~s(database "#{scratch_opts[:database]}" has objects outside the Hologram schemas that depend on them, which the reset would delete too: constraint payment_post_id_fkey on table payment - drop them or remove their dependency on the Hologram tables, then run the reset again)

      assert_raise RuntimeError, message, fn -> reset!(database_opts, :hologram, :dev) end

      assert post_rows(scratch_opts) == [[7]]
    end

    test "refuses when a view outside the Hologram schemas reads them", %{
      database_opts: database_opts,
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      claim(scratch)

      query!(
        scratch,
        ~s[CREATE VIEW "public"."post_ids" AS SELECT "id" FROM "hologram_data"."post"]
      )

      disconnect(scratch_opts)

      assert_raise RuntimeError, ~r/: rule _RETURN on view post_ids - /, fn ->
        reset!(database_opts, :hologram, :dev)
      end

      assert post_rows(scratch_opts) == [[7]]
    end

    test "refuses when a column outside the Hologram schemas has a Hologram type", %{
      database_opts: database_opts,
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      claim(scratch)
      query!(scratch, ~s[CREATE TYPE "hologram_data"."mood" AS ENUM ('calm')])
      query!(scratch, ~s[CREATE TABLE "public"."diary" ("mood" "hologram_data"."mood")])
      disconnect(scratch_opts)

      assert_raise RuntimeError, ~r/: column mood of table diary - /, fn ->
        reset!(database_opts, :hologram, :dev)
      end

      assert post_rows(scratch_opts) == [[7]]
    end

    test "refuses when something depends on a Hologram schema itself", %{
      database_opts: database_opts,
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      claim(scratch)

      query!(
        scratch,
        ~s[ALTER DEFAULT PRIVILEGES IN SCHEMA "hologram_data" GRANT SELECT ON TABLES TO PUBLIC]
      )

      disconnect(scratch_opts)

      assert_raise RuntimeError,
                   ~r/: default privileges on new relations .* in schema hologram_data - /,
                   fn ->
                     reset!(database_opts, :hologram, :dev)
                   end

      assert post_rows(scratch_opts) == [[7]]
    end

    test "drops the members of a Hologram operator family", %{
      database_opts: database_opts,
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      claim(scratch)

      query!(scratch, """
      CREATE FUNCTION "hologram_data"."lt" (integer, integer) RETURNS boolean
      LANGUAGE sql IMMUTABLE AS 'SELECT $1 < $2'
      """)

      query!(scratch, """
      CREATE OPERATOR "hologram_data".<<< (
        LEFTARG = integer, RIGHTARG = integer, FUNCTION = "hologram_data"."lt"
      )
      """)

      query!(scratch, ~s[CREATE OPERATOR FAMILY "hologram_data"."family" USING btree])

      query!(scratch, """
      ALTER OPERATOR FAMILY "hologram_data"."family" USING btree
      ADD OPERATOR 1 "hologram_data".<<< (integer, integer)
      """)

      disconnect(scratch_opts)

      assert reset!(database_opts, :hologram, :dev) == :dropped

      assert hologram_schemas(scratch_opts) == []
    end

    test "drops views and foreign keys inside the Hologram schemas", %{
      database_opts: database_opts,
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      claim(scratch)

      query!(scratch, """
      CREATE TABLE "hologram_data"."comment" ("post_id" integer REFERENCES "hologram_data"."post")
      """)

      query!(
        scratch,
        ~s[CREATE VIEW "hologram_data"."post_ids" AS SELECT "id" FROM "hologram_data"."post"]
      )

      disconnect(scratch_opts)

      assert reset!(database_opts, :hologram, :dev) == :dropped

      assert hologram_schemas(scratch_opts) == []
    end

    test "refuses a database name PostgreSQL would cut" do
      long_name = String.duplicate("a", 64)

      message =
        ~s(database name "#{long_name}" is longer than PostgreSQL's limit of 63 bytes - configure a shorter one)

      assert_raise RuntimeError, message, fn ->
        reset!([database: long_name, host: "localhost", port: 1], :hologram, :dev)
      end
    end

    test "refuses every env but dev before connecting" do
      unreachable_opts = [
        database: "unused",
        host: "localhost",
        password: "x",
        port: 1,
        user: "x"
      ]

      assert_raise RuntimeError,
                   "the database reset runs in the dev env only - the current env is :test",
                   fn -> reset!(unreachable_opts, :hologram, :test) end
    end

    test "names the server it couldn't connect to" do
      unreachable_opts = [
        database: "unused",
        host: "localhost",
        password: "postgres",
        port: 1,
        user: "postgres"
      ]

      capture_log(fn ->
        assert_raise RuntimeError,
                     ~r/^could not connect to database "postgres" at localhost:1 as user "postgres": /,
                     fn -> reset!(unreachable_opts, :hologram, :dev) end
      end)
    end
  end
end
