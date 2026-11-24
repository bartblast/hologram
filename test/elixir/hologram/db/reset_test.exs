defmodule Hologram.DB.ResetTest do
  use Hologram.Test.ScratchDatabaseCase, async: true

  import ExUnit.CaptureLog
  import Hologram.DB.Reset

  alias Hologram.DB.Config
  alias Hologram.DB.Mapper
  alias Hologram.DB.SchemaReconciler
  alias Hologram.Test.DatabaseBootstrap

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

  # A database next to the test's scratch one, dropped after the test whatever the sweep did.
  defp create_database(scratch_opts, database, owner \\ nil) do
    quoted_database = Mapper.quote_identifier(database)
    owner_clause = if owner, do: " OWNER #{Mapper.quote_identifier(owner)}", else: ""

    with_maintenance(scratch_opts, fn maintenance ->
      query!(maintenance, "CREATE DATABASE #{quoted_database} TEMPLATE template0#{owner_clause}")
    end)

    on_exit(fn ->
      with_maintenance(scratch_opts, fn maintenance ->
        query!(maintenance, "DROP DATABASE IF EXISTS #{quoted_database} WITH (FORCE)")
      end)
    end)

    database
  end

  # A role of the test's own, dropped once the databases it owns are: on_exit callbacks run in
  # reverse order, so the role's, registered before theirs, runs after them.
  defp create_role(scratch_opts, suffix, attributes) do
    role = scratch_opts[:database] <> suffix
    quoted_role = Mapper.quote_identifier(role)

    with_maintenance(scratch_opts, fn maintenance ->
      query!(maintenance, "CREATE ROLE #{quoted_role} #{attributes}")
    end)

    on_exit(fn ->
      with_maintenance(scratch_opts, fn maintenance ->
        query!(maintenance, "DROP ROLE IF EXISTS #{quoted_role}")
      end)
    end)

    role
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
  # no session is one another run's bootstrap drops.
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

  # Without the relisting interval, which the tests have no run to wait out.
  defp drop_leftovers!(database_opts, leftovers) do
    drop_leftovers!(database_opts, :test, leftovers, relisting_interval_ms: 0)
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

  defp existing_databases(scratch_opts, databases) do
    with_maintenance(scratch_opts, fn maintenance ->
      %{rows: rows} =
        Postgrex.query!(
          maintenance,
          ~s{SELECT "datname" FROM pg_catalog.pg_database WHERE "datname" = ANY($1)},
          [databases]
        )

      rows
      |> Enum.map(fn [database] -> database end)
      |> Enum.sort()
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

  # The leftovers of a test: run databases of its scratch database only, so it never reaches a
  # database of anyone else's.
  defp own_leftovers(scratch_opts, overrides \\ []) do
    Map.merge(
      %{databases: [], run_bases: [scratch_opts[:database]]},
      Map.new(overrides)
    )
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

  describe "drop_leftovers!/4" do
    # The marked database belongs to a role of its own, since every run's bootstrap drops the
    # marked databases of its own role that have no session.
    @tag :requires_superuser
    test "drops the run databases of a run base, marked or not", %{
      database_opts: database_opts,
      scratch_opts: scratch_opts
    } do
      base = scratch_opts[:database]
      owner = create_role(scratch_opts, "_owner", "NOLOGIN")

      unmarked =
        create_database(scratch_opts, DatabaseBootstrap.run_database_name(base, "0123abcd"))

      marked =
        create_database(
          scratch_opts,
          DatabaseBootstrap.run_database_name(base, "4567cdef"),
          owner
        )

      with_maintenance(scratch_opts, fn maintenance ->
        query!(
          maintenance,
          "COMMENT ON DATABASE #{Mapper.quote_identifier(marked)} IS '#{DatabaseBootstrap.mark()}'"
        )
      end)

      assert drop_leftovers!(database_opts, own_leftovers(scratch_opts)) == %{
               dropped: Enum.sort([unmarked, marked]),
               skipped: []
             }

      assert existing_databases(scratch_opts, [unmarked, marked]) == []
    end

    test "drops the run database of a base long enough for its name to be cut", %{
      database_opts: database_opts,
      scratch_opts: scratch_opts
    } do
      scratch_database = scratch_opts[:database]
      base = scratch_database <> String.duplicate("l", 63 - byte_size(scratch_database))

      run_database =
        create_database(scratch_opts, DatabaseBootstrap.run_database_name(base, "0123abcd"))

      refute String.starts_with?(run_database, base)

      leftovers = own_leftovers(scratch_opts, run_bases: [base])

      assert drop_leftovers!(database_opts, leftovers) == %{dropped: [run_database], skipped: []}
      assert existing_databases(scratch_opts, [run_database]) == []
    end

    test "keeps databases that only look like run databases, and those of other bases", %{
      database_opts: database_opts,
      scratch_opts: scratch_opts
    } do
      base = scratch_opts[:database]

      kept =
        Enum.map(
          [
            base <> "_run_0123ABCD",
            base <> "_run_0123abc",
            base <> "_run_0123abcd_x",
            base <> "x_run_0123abcd",
            DatabaseBootstrap.run_database_name(base <> "_other", "0123abcd")
          ],
          &create_database(scratch_opts, &1)
        )

      assert drop_leftovers!(database_opts, own_leftovers(scratch_opts)) == %{
               dropped: [],
               skipped: []
             }

      assert existing_databases(scratch_opts, kept) == Enum.sort(kept)
    end

    test "drops the named databases and the shadows of the run bases and run databases", %{
      database_opts: database_opts,
      scratch_opts: scratch_opts
    } do
      base = scratch_opts[:database]
      legacy = create_database(scratch_opts, base <> "_legacy")
      legacy_shadow = create_database(scratch_opts, legacy <> "_shadow")

      run_database =
        create_database(scratch_opts, DatabaseBootstrap.run_database_name(base, "0123abcd"))

      run_shadow = create_database(scratch_opts, run_database <> "_shadow")

      # The shadow of a run database that's gone.
      orphan_shadow =
        create_database(
          scratch_opts,
          DatabaseBootstrap.run_database_name(base, "4567cdef") <> "_shadow"
        )

      # The configured database's own shadow, from before runs had databases of their own.
      configured_shadow = create_database(scratch_opts, base <> "_shadow")

      databases = [
        legacy,
        legacy_shadow,
        run_database,
        run_shadow,
        orphan_shadow,
        configured_shadow
      ]

      leftovers = own_leftovers(scratch_opts, databases: [legacy], run_bases: [base, legacy])

      assert drop_leftovers!(database_opts, leftovers) == %{
               dropped: Enum.sort(databases),
               skipped: []
             }

      assert existing_databases(scratch_opts, databases) == []
    end

    test "skips a database a session is connected to", %{
      database_opts: database_opts,
      scratch_opts: scratch_opts
    } do
      run_database =
        create_database(
          scratch_opts,
          DatabaseBootstrap.run_database_name(scratch_opts[:database], "0123abcd")
        )

      scratch_opts
      |> Keyword.put(:database, run_database)
      |> with_session(fn connection ->
        query!(connection, "SELECT 1")
        started_at = System.monotonic_time(:millisecond)

        assert drop_leftovers!(database_opts, own_leftovers(scratch_opts)) == %{
                 dropped: [],
                 skipped: [{run_database, :in_use}]
               }

        # A DROP DATABASE refused for a session takes 5 seconds, so a quick skip comes from a
        # check before the DROP.
        assert System.monotonic_time(:millisecond) - started_at < 2_000
      end)

      assert existing_databases(scratch_opts, [run_database]) == [run_database]
    end

    test "skips a database a session was connected to at the first listing", %{
      database_opts: database_opts,
      scratch_opts: scratch_opts
    } do
      run_database =
        create_database(
          scratch_opts,
          DatabaseBootstrap.run_database_name(scratch_opts[:database], "0123abcd")
        )

      {:ok, session} =
        scratch_opts
        |> Keyword.put(:database, run_database)
        |> Postgrex.start_link()

      Postgrex.query!(session, "SELECT 1", [])

      # Wide margins: the first listing has to come before the close, and the second long after.
      Task.start(fn ->
        Process.sleep(500)
        GenServer.stop(session)
      end)

      leftovers = own_leftovers(scratch_opts)

      assert drop_leftovers!(database_opts, :test, leftovers, relisting_interval_ms: 3_000) == %{
               dropped: [],
               skipped: [{run_database, :in_use}]
             }

      assert existing_databases(scratch_opts, [run_database]) == [run_database]
    end

    test "keeps the shadow of a run database a session connected to between the listings", %{
      database_opts: database_opts,
      scratch_opts: scratch_opts
    } do
      run_database =
        create_database(
          scratch_opts,
          DatabaseBootstrap.run_database_name(scratch_opts[:database], "0123abcd")
        )

      shadow = create_database(scratch_opts, run_database <> "_shadow")
      test_pid = self()

      # Connects well after the first listing and stays until the sweep is done.
      session =
        Task.async(fn ->
          Process.sleep(500)

          {:ok, connection} =
            scratch_opts
            |> Keyword.put(:database, run_database)
            |> Postgrex.start_link()

          Postgrex.query!(connection, "SELECT 1", [])
          send(test_pid, :connected)

          receive do
            :done -> GenServer.stop(connection)
          end
        end)

      leftovers = own_leftovers(scratch_opts)

      assert drop_leftovers!(database_opts, :test, leftovers, relisting_interval_ms: 3_000) == %{
               dropped: [],
               skipped: [{run_database, :in_use}]
             }

      assert_received :connected
      send(session.pid, :done)
      Task.await(session)

      assert existing_databases(scratch_opts, [run_database, shadow]) ==
               Enum.sort([run_database, shadow])
    end

    test "keeps a run database whose shadow is skipped", %{
      database_opts: database_opts,
      scratch_opts: scratch_opts
    } do
      run_database =
        create_database(
          scratch_opts,
          DatabaseBootstrap.run_database_name(scratch_opts[:database], "0123abcd")
        )

      shadow = create_database(scratch_opts, run_database <> "_shadow")

      scratch_opts
      |> Keyword.put(:database, shadow)
      |> with_session(fn connection ->
        query!(connection, "SELECT 1")

        assert drop_leftovers!(database_opts, own_leftovers(scratch_opts)) == %{
                 dropped: [],
                 skipped: [{run_database, :shadow_kept}, {shadow, :in_use}]
               }
      end)

      assert existing_databases(scratch_opts, [run_database, shadow]) ==
               Enum.sort([run_database, shadow])
    end

    test "keeps the shadow of a run database it skips, without reporting it", %{
      database_opts: database_opts,
      scratch_opts: scratch_opts
    } do
      run_database =
        create_database(
          scratch_opts,
          DatabaseBootstrap.run_database_name(scratch_opts[:database], "0123abcd")
        )

      shadow = create_database(scratch_opts, run_database <> "_shadow")

      scratch_opts
      |> Keyword.put(:database, run_database)
      |> with_session(fn connection ->
        query!(connection, "SELECT 1")

        assert drop_leftovers!(database_opts, own_leftovers(scratch_opts)) == %{
                 dropped: [],
                 skipped: [{run_database, :in_use}]
               }
      end)

      assert existing_databases(scratch_opts, [run_database, shadow]) ==
               Enum.sort([run_database, shadow])
    end

    test "never drops the configured database, whatever it's named", %{
      database_opts: database_opts,
      scratch_opts: scratch_opts
    } do
      configured =
        create_database(
          scratch_opts,
          DatabaseBootstrap.run_database_name(scratch_opts[:database], "0123abcd")
        )

      leftovers = own_leftovers(scratch_opts, databases: [configured])

      assert drop_leftovers!(Keyword.put(database_opts, :database, configured), leftovers) == %{
               dropped: [],
               skipped: []
             }

      assert existing_databases(scratch_opts, [configured]) == [configured]
    end

    @tag :requires_superuser
    test "drops a database of a role the configured one can act as, and skips one of another", %{
      database_opts: database_opts,
      scratch_opts: scratch_opts
    } do
      user = create_role(scratch_opts, "_user", "LOGIN PASSWORD 'scratch'")
      owner = create_role(scratch_opts, "_owner", "NOLOGIN")
      stranger = create_role(scratch_opts, "_stranger", "NOLOGIN")

      with_maintenance(scratch_opts, fn maintenance ->
        query!(
          maintenance,
          "GRANT #{Mapper.quote_identifier(owner)} TO #{Mapper.quote_identifier(user)}"
        )
      end)

      base = scratch_opts[:database]

      owned =
        create_database(
          scratch_opts,
          DatabaseBootstrap.run_database_name(base, "0123abcd"),
          owner
        )

      foreign =
        create_database(
          scratch_opts,
          DatabaseBootstrap.run_database_name(base, "4567cdef"),
          stranger
        )

      user_opts = [{:user, user}, {:password, "scratch"} | database_opts]

      assert drop_leftovers!(user_opts, own_leftovers(scratch_opts)) == %{
               dropped: [owned],
               skipped: [{foreign, :not_owner}]
             }

      assert existing_databases(scratch_opts, [owned, foreign]) == [foreign]
    end

    test "refuses every env but test before connecting" do
      unreachable_opts = [
        database: "unused",
        host: "localhost",
        password: "x",
        port: 1,
        user: "x"
      ]

      assert_raise RuntimeError,
                   "the leftover sweep runs in the test env only - the current env is :dev",
                   fn ->
                     drop_leftovers!(unreachable_opts, :dev, own_leftovers(database: "unused"))
                   end
    end
  end

  describe "leftovers/2" do
    test "names the configured database's run databases" do
      assert leftovers(:my_app, "my_app_test") == %{
               databases: [],
               run_bases: ["my_app_test"]
             }
    end

    test "names the cluster tests' migrations database and its run databases" do
      assert leftovers(:hologram_cluster_tests, "hologram_cluster_tests_test") == %{
               databases: ["hologram_cluster_tests_migrations"],
               run_bases: ["hologram_cluster_tests_test", "hologram_cluster_tests_migrations"]
             }
    end

    test "leaves the configured database out when it has a legacy database's name" do
      assert leftovers(:hologram_cluster_tests, "hologram_cluster_tests_migrations") == %{
               databases: [],
               run_bases: ["hologram_cluster_tests_migrations"]
             }
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

    @tag :requires_superuser
    test "says how many sessions its user can't see the kind of", %{
      database_opts: database_opts,
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      role = create_role(scratch_opts, "_role", "LOGIN PASSWORD 'scratch'")
      quoted_role = Mapper.quote_identifier(role)

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

    test "resets a test database the same way", %{
      database_opts: database_opts,
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      claim(scratch, %{@claim | env: "test"})
      query!(scratch, ~s[CREATE TABLE "public"."kept" ("id" integer)])
      query!(scratch, ~s[INSERT INTO "public"."kept" VALUES (1)])
      disconnect(scratch_opts)

      assert reset!(database_opts, :hologram, :test) == :dropped

      assert hologram_schemas(scratch_opts) == []
      assert other_table_rows(scratch_opts) == [[1]]
    end

    test "refuses every env but dev and test before connecting" do
      unreachable_opts = [
        database: "unused",
        host: "localhost",
        password: "x",
        port: 1,
        user: "x"
      ]

      assert_raise RuntimeError,
                   "the database reset runs in the dev and test envs only - the current env is :prod",
                   fn -> reset!(unreachable_opts, :hologram, :prod) end
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
