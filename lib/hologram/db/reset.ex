defmodule Hologram.DB.Reset do
  @moduledoc false

  # The database steps of mix holo.db.reset: everything that touches the server, and nothing
  # that runs Mix, so the steps can be tested on scratch databases. The task resolves the
  # connection options, guards the env, and rebuilds and seeds afterwards.

  alias Hologram.DB.Mapper
  alias Hologram.Test.DatabaseBootstrap
  alias Hologram.Test.DatabaseBootstrap.Connection

  # The shared databases an app's test runs used before each run got databases of its own,
  # besides the configured one: the test env reset drops them by name. No marker guard could
  # tell the cluster tests' migrations database, which they claim as the prod env's.
  @legacy_databases %{hologram_cluster_tests: ["hologram_cluster_tests_migrations"]}

  # How long apart the leftover sweep lists the databases. A database a run has just created has
  # no session until the run connects to it, a moment later, so only a database both listings
  # show without one is taken for a leftover.
  @relisting_interval_ms 1_000

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

  @typedoc """
  The databases drop_leftovers!/4 removes: the ones named, every run database of a run base (see
  Hologram.Test.DatabaseBootstrap.run_database_name/2), the shadow verifier's scratch database of
  a run base or a run database, and, with a scratch prefix, the scratch databases named with it.
  """
  @type leftovers :: %{
          databases: list(String.t()),
          run_bases: list(String.t()),
          scratch_prefix: String.t() | nil
        }

  @typedoc """
  What drop_leftovers!/4 did: the databases it dropped, and the ones it left, with why - a session
  connected to it, a role the configured one can't drop the databases of owns it, or its shadow
  was left, which a later sweep finds only through it.
  """
  @type sweep :: %{
          dropped: list(String.t()),
          skipped: list({String.t(), :in_use | :not_owner | :shadow_kept})
        }

  @doc """
  Drops the leftovers of earlier test runs the given spec names (see leftovers/2), on the server
  the given resolved options name, and returns what it dropped and skipped.

  Goes by name, marked or not, so it reaches the databases of runs killed before they marked
  them, and those of runs from before the mark. A database with a session is skipped, never
  ended, and so is one a role the configured one can't act as owns. The databases are listed
  twice, the interval apart, and only those both listings show are dropped, so a database a run
  has just created and not yet connected to is left alone. A shadow goes before the database it
  was named after, and a database whose shadow is left stays too, as in the test runs' own
  sweep. The configured database is never dropped, whatever it's named.

  Runs in the test env only. The options take :relisting_interval_ms, which defaults to a second.
  """
  @spec drop_leftovers!(keyword, atom, leftovers, keyword) :: sweep
  def drop_leftovers!(database_opts, env, leftovers, opts \\ []) do
    refuse_non_test_env!(env)

    relisting_interval_ms = Keyword.get(opts, :relisting_interval_ms, @relisting_interval_ms)

    {:ok, _started} = Application.ensure_all_started(:postgrex)

    database = database_opts[:database]

    with_connection(database_opts, "postgres", fn pid ->
      first_listing = list_leftovers(pid, leftovers, database)
      Process.sleep(relisting_interval_ms)

      # Compared by oid too, so a database dropped and created again under its name between the
      # listings counts as new.
      listed =
        pid
        |> list_leftovers(leftovers, database)
        |> Map.filter(fn {name, listed} -> first_listing[name][:oid] == listed.oid end)

      drop_listed_leftovers(pid, listed, first_listing)
    end)
  end

  @doc """
  Returns the leftovers the test env reset of the given app drops (see drop_leftovers!/4), besides
  the given configured test database, which it keeps: the app's legacy shared databases, the run
  databases of the configured one and of those, the shadows of all of them, among them the
  configured one's from before runs had databases of their own, and, for Hologram's own suite,
  its scratch databases.
  """
  @spec leftovers(atom, String.t()) :: leftovers
  def leftovers(otp_app, database) do
    legacy_databases = Map.get(@legacy_databases, otp_app, [])

    %{
      databases: legacy_databases -- [database],
      run_bases: Enum.uniq([database | legacy_databases]),
      scratch_prefix: if(otp_app == :hologram, do: DatabaseBootstrap.scratch_prefix())
    }
  end

  @doc """
  Clears the Hologram part of the database the given resolved options name (see
  Hologram.DB.Config.resolve!/2), so its schema can be built from nothing. Returns the outcome.

  A missing database is created. A present one loses the hologram_data and hologram_system
  schemas and nothing else, so tables of an Ecto repo sharing it stay. Refuses, changing
  nothing, while another client is connected to the database, when its marker says it belongs
  to another app, another env, or the migrator - the given app and env are the current ones -
  or when something outside the two schemas depends on them, which the drop would take along.

  Runs in the dev and test envs only.
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

  # Looked up again right before the drop, so one created under the name since the second listing
  # is never taken for the leftover, which matters for a shadow, whose name the verifier reuses.
  # Without FORCE, so a session that connected since is never ended, and IF EXISTS, since a test
  # run's own sweep may have got there first. A database that's gone or was replaced isn't
  # reported.
  defp drop_leftover(pid, name, %{oid: listed_oid} = listed, first_listed) do
    with nil <- leftover_refusal(listed, first_listed),
         %{^name => %{oid: ^listed_oid} = current} <-
           list_databases(pid, ~s("d"."datname" = #{literal(name)})),
         nil <- leftover_refusal(current, current) do
      Connection.query!(pid, "DROP DATABASE IF EXISTS #{quote_name(name)}")
      :dropped
    else
      reason when reason in [:in_use, :not_owner] -> reason
      _gone_or_replaced -> :gone
    end
  rescue
    error in Postgrex.Error ->
      case error do
        %Postgrex.Error{postgres: %{code: :object_in_use}} -> :in_use
        _other -> reraise error, __STACKTRACE__
      end
  end

  # A database and its shadow go together, the shadow first: dropped or kept on their own, a
  # shadow whose database is gone is found by no later sweep when the database's name was cut, and
  # a live run's shadow could go with its database kept. A pair whose database is skipped keeps its
  # shadow unreported. No listed shadow has a listed shadow of its own, since no run base or named
  # database ends in _shadow, so a pair is never part of a longer chain.
  defp drop_listed_leftovers(pid, listed, first_listing) do
    shadows =
      for {name, _listed} <- listed,
          shadow = shadow_name(name),
          Map.has_key?(listed, shadow),
          into: %{},
          do: {name, shadow}

    paired_shadows =
      shadows
      |> Map.values()
      |> MapSet.new()

    listed
    |> Map.keys()
    |> Enum.reject(&MapSet.member?(paired_shadows, &1))
    |> Enum.sort()
    |> Enum.reduce(%{dropped: [], skipped: []}, fn name, sweep ->
      case leftover_refusal(listed[name], first_listing[name]) do
        nil ->
          pair = Enum.reject([shadows[name], name], &is_nil/1)
          drop_pair(pid, pair, listed, first_listing, sweep)

        reason ->
          %{sweep | skipped: [{name, reason} | sweep.skipped]}
      end
    end)
    |> Map.new(fn {key, names} -> {key, Enum.sort(names)} end)
  end

  defp drop_pair(_pid, [], _listed, _first_listing, sweep), do: sweep

  defp drop_pair(pid, [name | rest], listed, first_listing, sweep) do
    case drop_leftover(pid, name, listed[name], first_listing[name]) do
      :dropped ->
        drop_pair(pid, rest, listed, first_listing, %{sweep | dropped: [name | sweep.dropped]})

      :gone ->
        drop_pair(pid, rest, listed, first_listing, sweep)

      reason ->
        skipped = Enum.map(rest, &{&1, :shadow_kept})
        %{sweep | skipped: [{name, reason} | skipped ++ sweep.skipped]}
    end
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

  # Why the sweep leaves a database, by both listings, or nil when it doesn't.
  defp leftover_refusal(listed, first_listed) do
    cond do
      not listed.droppable? -> :not_owner
      listed.in_use? or first_listed.in_use? -> :in_use
      true -> nil
    end
  end

  # The databases the condition selects, with their oids, whether the configured role can drop
  # them and whether a session is connected to them. A role can drop a database when it can act
  # as its owner, which a superuser always can. A session counts as in the session check of the
  # reset.
  defp list_databases(pid, condition) do
    statement = """
    SELECT "d"."oid", "d"."datname", pg_catalog.pg_has_role(current_user, "d"."datdba", 'USAGE'),
      EXISTS (
        SELECT 1 FROM pg_catalog.pg_stat_activity AS "a"
        WHERE "a"."datid" = "d"."oid"
          AND ("a"."backend_type" = 'client backend'
            OR ("a"."backend_type" IS NULL AND "a"."usesysid" IS NOT NULL))
      )
    FROM pg_catalog.pg_database AS "d"
    WHERE NOT "d"."datistemplate" AND #{condition}
    """

    Map.new(Connection.query!(pid, statement).rows, fn [oid, name, droppable, in_use] ->
      {name, %{oid: oid, droppable?: droppable == "t", in_use?: in_use == "t"}}
    end)
  end

  # Every database the spec names that's on the server but the configured one (see
  # list_databases/2). Matched here rather than in SQL, by the functions that name the databases.
  defp list_leftovers(pid, leftovers, configured_database) do
    databases = list_databases(pid, ~s("d"."datname" <> #{literal(configured_database)}))

    run_databases =
      databases
      |> Map.keys()
      |> Enum.filter(&run_database?(&1, leftovers.run_bases))

    shadows = MapSet.new(leftovers.run_bases ++ run_databases, &shadow_name/1)

    Map.filter(databases, fn {name, _listed} ->
      name in leftovers.databases or name in run_databases or MapSet.member?(shadows, name) or
        orphan_shadow?(name, leftovers.run_bases) or
        scratch_database?(name, leftovers.scratch_prefix)
    end)
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

  # The shadow of a run database that's gone, which a sweep stopped between the two drops leaves.
  # Found only when the run database's name was short enough to keep the suffix whole.
  defp orphan_shadow?(name, run_bases) do
    String.ends_with?(name, "_shadow") and
      name
      |> String.replace_suffix("_shadow", "")
      |> run_database?(run_bases)
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

  defp refuse_env!(env) when env in [:dev, :test], do: :ok

  defp refuse_env!(env) do
    raise "the database reset runs in the dev and test envs only - the current env is " <>
            inspect(env)
  end

  defp refuse_long_name!(database) do
    if byte_size(database) > @max_name_bytes do
      raise ~s(database name "#{database}" is longer than PostgreSQL's limit of ) <>
              "#{@max_name_bytes} bytes - configure a shorter one"
    end
  end

  defp refuse_non_test_env!(:test), do: :ok

  defp refuse_non_test_env!(env) do
    raise "the leftover sweep runs in the test env only - the current env is #{inspect(env)}"
  end

  # A run database's name is a function of its base and its run id, so a name counts when the
  # function gives it back from the run id it ends with. A name that only looks like one, or one
  # whose base was cut differently, doesn't.
  defp run_database?(name, run_bases) do
    case Regex.run(~r/_run_([0-9a-f]{8})$/, name) do
      [_suffix, run_id] ->
        Enum.any?(run_bases, &(DatabaseBootstrap.run_database_name(&1, run_id) == name))

      nil ->
        false
    end
  end

  # What Hologram.Test.ScratchDatabaseCase names them: the prefix, the run's OS process id and a
  # counter.
  defp scratch_database?(_name, nil), do: false

  defp scratch_database?(name, prefix) do
    case String.split_at(name, String.length(prefix)) do
      {^prefix, rest} -> Regex.match?(~r/^[0-9]+_[0-9]+$/, rest)
      _other -> false
    end
  end

  defp sessions("1"), do: "1 other session is"

  defp sessions(count), do: "#{count} other sessions are"

  # As the shadow verifier names it.
  defp shadow_name(database), do: Mapper.fit_identifier([database], [], "shadow")

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
