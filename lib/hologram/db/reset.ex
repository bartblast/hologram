defmodule Hologram.DB.Reset do
  @moduledoc false

  # The database steps of mix holo.db.reset: everything that touches the server, and nothing
  # that runs Mix, so the steps can be tested on scratch databases. The task resolves the
  # connection options, guards the env, and rebuilds and seeds afterwards.

  alias Hologram.DB.Mapper
  alias Hologram.Test.DatabaseBootstrap.Connection

  # How long the reset waits for a lock a client that connected after the session check holds,
  # before it gives up instead of hanging the task.
  @lock_timeout "10s"

  # PostgreSQL cuts a longer name without saying so, and not the same way everywhere: CREATE
  # DATABASE cuts at a character boundary, a connection at the byte. A name with a character
  # across the limit then creates a database no connection reaches, and a shorter cut name is
  # never the config's anyway.
  @max_name_bytes 63

  @typedoc """
  What reset!/3 did to the configured database: created it, dropped its Hologram schemas, or
  found it without any.
  """
  @type outcome :: :created | :dropped | :empty

  @doc """
  Clears the Hologram part of the database the given resolved options name (see
  Hologram.DB.Config.resolve!/2), so the next boot builds it from nothing. Returns the outcome.

  A missing database is created. A present one loses the hologram_data and hologram_system
  schemas and nothing else, so tables of an Ecto repo sharing it stay. Refuses, changing
  nothing, while another client is connected to the database, when its marker says it belongs
  to another app, another env, or the migrator - the given app and env are the current ones -
  or when something outside the two schemas depends on them, which the drop would take along.

  Runs in the dev env only, the one whose boot builds the schema from the model.
  """
  @spec reset!(keyword, atom, atom) :: outcome
  def reset!(database_opts, otp_app, env) do
    refuse_env!(env)

    database = database_opts[:database]
    refuse_long_name!(database)

    {:ok, _started} = Application.ensure_all_started(:postgrex)

    with_connection(database_opts, "postgres", fn maintenance_pid ->
      if database_exists?(maintenance_pid, database) do
        with_connection(database_opts, database, &clear!(&1, database, otp_app, env))
      else
        create_database!(maintenance_pid, database)
        :created
      end
    end)
  end

  defp check_marker!(pid, database, otp_app, env) do
    case read_marker(pid, database) do
      nil ->
        :ok

      %{otp_app: marker_app} when marker_app != otp_app ->
        raise ~s(database "#{database}" belongs to app "#{marker_app}" - the current app is ) <>
                ~s("#{otp_app}" - the reset leaves another app's database alone, ) <>
                "point the config at the right database"

      %{env: marker_env} when marker_env != env ->
        raise ~s(database "#{database}" belongs to the "#{marker_env}" env - the current env ) <>
                ~s(is "#{env}" - the reset leaves another env's database alone, ) <>
                "point the config at the right database"

      %{managed_by: "reconciliation"} ->
        :ok

      %{managed_by: managed_by} ->
        raise ~s(database "#{database}" is managed by #{managed_by} - the reset clears only ) <>
                "a database schema reconciliation manages"
    end
  end

  # Only client sessions count: autovacuum and the other background workers come and go on
  # their own, and none of them is the user's. A role that's neither a superuser nor a member of
  # pg_read_all_stats sees no backend_type for another role's session, so a session of another
  # role counts unless it has no user, like autovacuum. A background worker that runs as a user
  # and stays connected, like an extension's scheduler, then counts too, so the refusal says how
  # many sessions the role couldn't see the kind of, and how to let it see.
  defp check_no_other_sessions!(pid, database) do
    statement = """
    SELECT count(*), count(*) FILTER (WHERE "backend_type" IS NULL), current_user
    FROM pg_catalog.pg_stat_activity
    WHERE "datname" = current_database() AND "pid" <> pg_backend_pid()
      AND ("backend_type" = 'client backend' OR ("backend_type" IS NULL AND "usesysid" IS NOT NULL))
    """

    case Connection.query!(pid, statement).rows do
      [["0", _hidden, _user]] ->
        :ok

      [[count, hidden, user]] ->
        raise "#{sessions(count)} connected to database \"#{database}\" - stop the app and " <>
                "close every other client of it, like psql, then run the reset again" <>
                hidden_sessions_hint(hidden, user)
    end
  end

  # A view, foreign key or column outside the two schemas that depends on something inside them
  # goes with them under CASCADE, and no boot builds it back, since it's not Hologram's. So does
  # an object that depends on a schema itself, like an extension or default privileges created in
  # it. Rules, triggers, policies and defaults carry no schema of their own, so theirs is their
  # table's, and an operator family member's is its family's. One with no schema found counts as
  # outside, so a miss refuses rather than drops. Internal dependencies, like a table's TOAST
  # table, go with their owner and are left out.
  defp check_no_outside_dependents!(pid, database) do
    hologram_schemas = "#{literal(Mapper.data_schema())}, #{literal(Mapper.system_schema())}"

    statement = """
    SELECT DISTINCT pg_catalog.pg_describe_object("d"."classid", "d"."objid", "d"."objsubid")
    FROM pg_catalog.pg_depend AS "d"
    CROSS JOIN LATERAL
      pg_catalog.pg_identify_object("d"."classid", "d"."objid", "d"."objsubid") AS "dependent"
    CROSS JOIN LATERAL
      pg_catalog.pg_identify_object("d"."refclassid", "d"."refobjid", "d"."refobjsubid")
      AS "referenced"
    WHERE "d"."deptype" IN ('n', 'a')
      AND ("referenced"."schema" IN (#{hologram_schemas})
        OR ("d"."refclassid" = 'pg_catalog.pg_namespace'::regclass
          AND "referenced"."name" IN (#{hologram_schemas})))
      AND COALESCE("dependent"."schema", CASE "d"."classid"
    #{owner_schema_cases()}
      END, '') NOT IN (#{hologram_schemas})
    ORDER BY 1
    """

    case Connection.query!(pid, statement).rows do
      [] ->
        :ok

      rows ->
        dependents = Enum.map_join(rows, ", ", fn [description] -> description end)

        raise ~s(database "#{database}" has objects outside the Hologram schemas that depend ) <>
                "on them, which the reset would delete too: #{dependents} - drop them or " <>
                "remove their dependency on the Hologram tables, then run the reset again"
    end
  end

  # A session-wide lock timeout, which the connection's end clears: a client that connected after
  # the session check and holds a lock the reset needs makes it fail instead of hanging.
  defp clear!(pid, database, otp_app, env) do
    check_no_other_sessions!(pid, database)

    Connection.query!(pid, "SET lock_timeout = #{literal(@lock_timeout)}")

    if hologram_schemas?(pid) do
      check_marker!(pid, database, Atom.to_string(otp_app), Atom.to_string(env))
      check_no_outside_dependents!(pid, database)
      drop_hologram_schemas!(pid)

      :dropped
    else
      :empty
    end
  rescue
    error in Postgrex.Error ->
      case error do
        %Postgrex.Error{postgres: %{code: :lock_not_available}} ->
          message =
            "a client connected to database \"#{database}\" while the reset ran and " <>
              "holds its tables - stop the app and close every other client of it, " <>
              "then run the reset again"

          reraise RuntimeError, [message: message], __STACKTRACE__

        _other ->
          reraise error, __STACKTRACE__
      end
  end

  # Created from template0, which holds nothing: template1 may have been customised.
  defp create_database!(pid, database) do
    Connection.query!(pid, "CREATE DATABASE #{quote_name(database)} TEMPLATE template0")
  end

  defp database_exists?(pid, database) do
    statement = """
    SELECT 1 FROM pg_catalog.pg_database WHERE "datname" = #{literal(database)}
    """

    Connection.query!(pid, statement).rows != []
  end

  # One statement, so both schemas go or neither does.
  defp drop_hologram_schemas!(pid) do
    Connection.query!(
      pid,
      "DROP SCHEMA IF EXISTS #{quote_name(Mapper.data_schema())}, " <>
        "#{quote_name(Mapper.system_schema())} CASCADE"
    )
  end

  defp hidden_sessions_hint("0", _user), do: ""

  defp hidden_sessions_hint(hidden, user) do
    ~s( - user "#{user}" can't see what #{hidden} of them is, and a background worker counts ) <>
      "too then - a superuser running GRANT pg_read_all_stats TO #{quote_name(user)} lets the " <>
      "reset tell"
  end

  defp hologram_schemas?(pid) do
    statement = """
    SELECT 1 FROM pg_catalog.pg_namespace
    WHERE "nspname" IN (#{literal(Mapper.data_schema())}, #{literal(Mapper.system_schema())})
    """

    Connection.query!(pid, statement).rows != []
  end

  # An escape string with backslashes and quotes doubled, read the same whatever
  # standard_conforming_strings says.
  defp literal(value) do
    escaped =
      value
      |> String.replace("\\", "\\\\")
      |> String.replace("'", "''")

    "E'" <> escaped <> "'"
  end

  # The schema of an object that carries none, as SQL CASE branches on its catalog: a table's
  # for the first four, an operator family's for the last two.
  defp owner_schema_cases do
    owners = [
      {"pg_rewrite", "ev_class", "pg_class", "relnamespace"},
      {"pg_trigger", "tgrelid", "pg_class", "relnamespace"},
      {"pg_policy", "polrelid", "pg_class", "relnamespace"},
      {"pg_attrdef", "adrelid", "pg_class", "relnamespace"},
      {"pg_amop", "amopfamily", "pg_opfamily", "opfnamespace"},
      {"pg_amproc", "amprocfamily", "pg_opfamily", "opfnamespace"}
    ]

    Enum.map_join(owners, "\n", fn {catalog, owner_column, owner_catalog, namespace_column} ->
      """
          WHEN 'pg_catalog.#{catalog}'::regclass THEN (
            SELECT "n"."nspname" FROM pg_catalog.#{catalog} AS "x"
            JOIN pg_catalog.#{owner_catalog} AS "o" ON "o"."oid" = "x"."#{owner_column}"
            JOIN pg_catalog.pg_namespace AS "n" ON "n"."oid" = "o"."#{namespace_column}"
            WHERE "x"."oid" = "d"."objid"
          )\
      """
    end)
  end

  defp quote_name(identifier), do: Mapper.quote_identifier(identifier)

  # The guard facts only: a database from another system table layout can have other columns,
  # and it's one the reset has to be able to clear. to_regclass, so a missing table reads as no
  # marker rather than an error. More than one row is no state Hologram writes, so the reset
  # doesn't pick one.
  defp read_marker(pid, database) do
    marker_table = literal(quote_name(Mapper.system_schema()) <> ".\"database\"")

    %{rows: [[table]]} = Connection.query!(pid, "SELECT to_regclass(#{marker_table})")

    if table do
      statement = """
      SELECT "otp_app", "env", "managed_by" FROM #{quote_name(Mapper.system_schema())}."database"
      """

      case Connection.query!(pid, statement).rows do
        [] ->
          nil

        [[otp_app, env, managed_by]] ->
          %{otp_app: otp_app, env: env, managed_by: managed_by}

        _rows ->
          raise ~s(database "#{database}" has more than one Hologram marker row - ) <>
                  "the reset can't tell whose database it is"
      end
    end
  end

  defp refuse_env!(:dev), do: :ok

  defp refuse_env!(env) do
    raise "the database reset runs in the dev env only - the current env is #{inspect(env)}"
  end

  defp refuse_long_name!(database) do
    if byte_size(database) > @max_name_bytes do
      raise ~s(database name "#{database}" is longer than PostgreSQL's limit of ) <>
              "#{@max_name_bytes} bytes - configure a shorter one"
    end
  end

  defp sessions("1"), do: "1 other session is"

  defp sessions(count), do: "#{count} other sessions are"

  defp with_connection(database_opts, database, fun) do
    connection_opts = [
      database: database,
      hostname: database_opts[:host],
      password: database_opts[:password],
      port: database_opts[:port],
      username: database_opts[:user]
    ]

    case Connection.start(connection_opts) do
      {:ok, pid} ->
        try do
          fun.(pid)
        after
          Connection.stop(pid)
        end

      {:error, reason} ->
        raise "could not connect to database \"#{database}\" at " <>
                "#{database_opts[:host]}:#{database_opts[:port]} as user " <>
                "\"#{database_opts[:user]}\": #{Exception.message(reason)}"
    end
  end
end
