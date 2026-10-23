defmodule Hologram.Test.DatabaseBootstrapTest do
  # async: false - the tests mutate the HOLOGRAM_ENV variable and the :hologram app's
  # :database config, both BEAM-global.
  use Hologram.Test.ScratchDatabaseCase, async: false

  import Hologram.Test.DatabaseBootstrap

  alias Hologram.DB.Config
  alias Hologram.DB.Mapper
  alias Hologram.DB.SchemaReconciler

  @claim %{
    otp_app: "hologram",
    env: "test",
    hologram_version: "0.5.0",
    timestamp: ~U[2026-10-23 12:00:00.000000Z]
  }

  # The configured database is the one the running suite depends on, so every test points
  # the bootstrap at the test's own scratch database instead. The config is restored before
  # the case template drops that database: on_exit callbacks run in reverse order of
  # registration, and the template registers its drop first.
  setup %{scratch_opts: scratch_opts} do
    original_config = Application.get_env(:hologram, :database)
    original_env = System.get_env("HOLOGRAM_ENV")

    Application.put_env(:hologram, :database, database: scratch_opts[:database])

    on_exit(fn ->
      if original_config do
        Application.put_env(:hologram, :database, original_config)
      else
        Application.delete_env(:hologram, :database)
      end

      if original_env do
        System.put_env("HOLOGRAM_ENV", original_env)
      else
        System.delete_env("HOLOGRAM_ENV")
      end
    end)

    :ok
  end

  defp claim(scratch, context) do
    route(scratch, fn -> SchemaReconciler.ensure_managed!(context) end)
  end

  defp hologram_schemas(scratch) do
    statement = """
    SELECT nspname
    FROM pg_catalog.pg_namespace
    WHERE nspname IN ('hologram_data', 'hologram_system')
    ORDER BY nspname
    """

    %{rows: rows} = Postgrex.query!(scratch, statement, [])

    Enum.map(rows, fn [name] -> name end)
  end

  describe "run!/1" do
    test "returns :ok on a database holding no Hologram schemas", %{scratch: scratch} do
      assert run!() == :ok

      assert hologram_schemas(scratch) == []
    end

    test "drops the Hologram schemas of a database this app's test env has claimed", %{
      scratch: scratch
    } do
      claim(scratch, @claim)

      assert hologram_schemas(scratch) == ["hologram_data", "hologram_system"]

      run!()

      assert hologram_schemas(scratch) == []
    end

    test "drops the Hologram schemas of a database holding them without a marker table", %{
      scratch: scratch
    } do
      Postgrex.query!(scratch, ~s(CREATE SCHEMA "hologram_system"), [])
      Postgrex.query!(scratch, ~s(CREATE SCHEMA "hologram_data"), [])

      run!()

      assert hologram_schemas(scratch) == []
    end

    test "drops the Hologram schemas of a database whose marker table holds no row", %{
      scratch: scratch
    } do
      claim(scratch, @claim)
      Postgrex.query!(scratch, ~s(DELETE FROM "hologram_system"."database"), [])

      run!()

      assert hologram_schemas(scratch) == []
    end

    test "refuses a database another app has claimed", %{
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      claim(scratch, %{@claim | otp_app: "other_app"})

      expected_msg =
        ~s(database "#{scratch_opts[:database]}" belongs to the "test" env of app ) <>
          ~s("other_app" - Hologram.Test.DatabaseBootstrap.run!/1 drops Hologram's ) <>
          "schemas only in a database nothing has claimed or the \"test\" env of app " <>
          "\"hologram\" has claimed - point the test env's config :hologram, :database " <>
          "at another database"

      assert_error RuntimeError, expected_msg, fn -> run!() end

      assert hologram_schemas(scratch) == ["hologram_data", "hologram_system"]
    end

    test "refuses a database another env has claimed", %{
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      claim(scratch, %{@claim | env: "dev"})

      expected_msg =
        ~s(database "#{scratch_opts[:database]}" belongs to the "dev" env of app ) <>
          ~s("hologram" - Hologram.Test.DatabaseBootstrap.run!/1 drops Hologram's ) <>
          "schemas only in a database nothing has claimed or the \"test\" env of app " <>
          "\"hologram\" has claimed - point the test env's config :hologram, :database " <>
          "at another database"

      assert_error RuntimeError, expected_msg, fn -> run!() end

      assert hologram_schemas(scratch) == ["hologram_data", "hologram_system"]
    end

    test "refuses a given database another env has claimed", %{
      scratch: scratch,
      scratch_opts: scratch_opts
    } do
      claim(scratch, %{@claim | env: "dev"})

      # The configured database is one the bootstrap creates, so the refusal can only come
      # from the given one.
      configured_database = scratch_opts[:database] <> "_configured"
      Application.put_env(:hologram, :database, database: configured_database)

      on_exit(fn ->
        maintenance_opts = Config.connection_opts(database: "postgres")
        {:ok, connection} = Postgrex.start_link(maintenance_opts)

        quoted_database = Mapper.quote_identifier(configured_database)
        drop_statement = "DROP DATABASE IF EXISTS #{quoted_database} WITH (FORCE)"

        Postgrex.query!(connection, drop_statement, [])
        GenServer.stop(connection)
      end)

      expected_msg =
        ~s(database "#{scratch_opts[:database]}" belongs to the "dev" env of app ) <>
          ~s("hologram" - Hologram.Test.DatabaseBootstrap.run!/1 drops Hologram's ) <>
          "schemas only in a database nothing has claimed or the \"test\" env of app " <>
          "\"hologram\" has claimed - point the test env's config :hologram, :database " <>
          "at another database"

      assert_error RuntimeError, expected_msg, fn -> run!([scratch_opts[:database]]) end

      assert hologram_schemas(scratch) == ["hologram_data", "hologram_system"]
    end

    test "refuses to run outside the test env" do
      System.put_env("HOLOGRAM_ENV", "dev")

      expected_msg =
        "Hologram.Test.DatabaseBootstrap.run!/1 drops Hologram's schemas and runs " <>
          "in the test env only - the current env is :dev. When neither " <>
          "HOLOGRAM_ENV nor MIX_ENV is set, the test env is recognized by the " <>
          "running ExUnit server, so call run!/1 after ExUnit.start()."

      assert_error RuntimeError, expected_msg, fn -> run!() end
    end
  end
end
