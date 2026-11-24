defmodule Hologram.DB.SchemaReconciler do
  @moduledoc false

  require Logger

  alias Hologram.DB.Connection
  alias Hologram.DB.DDL
  alias Hologram.DB.IndexPlan
  alias Hologram.DB.Introspection
  alias Hologram.DB.Mapper
  alias Hologram.DB.Preflight
  alias Hologram.DB.Schema
  alias Hologram.DB.SortKey

  # Fixed application-defined key for pg_advisory_xact_lock - serializes concurrent
  # reconciliations from multiple VMs against one database (the second waits, then
  # introspects the converged state and gets an empty diff). The value is frozen
  # forever: a different key breaks mutual exclusion across Hologram versions, so it
  # must survive any code move or rename. Provenance (for uniqueness, not for
  # re-derivation): first 8 bytes of md5("hologram_schema_reconciliation") as a
  # signed int64.
  @advisory_lock_key 4_787_000_136_577_093_832

  # The ops the schema diff's pairing pass emits - a recognised rename, applied ahead of the
  # rest of the run.
  @rename_ops [:rename_enum_type, :rename_index, :rename_table]

  # Appended in dev to the refusals the reset clears: every one but those for another app's,
  # another env's or a migration-managed database, which the reset refuses too.
  @reset_hint " - or run mix holo.db.reset to start over, which deletes this database's " <>
                "Hologram data"

  @doc """
  Fills every derived companion column the given ops add - a sort key or a search key - from the
  companion's source column, one row at a time in the caller's transaction. The companion of a
  nil value is nil. Ops adding no companion are passed over. Returns :ok.
  """
  @spec backfill_companions!(list(%{atom => any}), %{module => %{atom => any}}) :: :ok
  def backfill_companions!(ops, mapping) do
    ops
    |> Enum.filter(&match?(%{op: :add_column}, &1))
    |> Enum.each(&backfill_op!(&1, mapping))
  end

  @doc """
  Raises when the given marker's hologram_system layout is newer than the running Hologram's - a
  database a later release claimed or upgraded, booted by an earlier one, whose code would read
  and write tables it doesn't know. Returns :ok otherwise. The running version follows the
  context (see system_schema_version/1).
  """
  @spec check_system_schema_version!(%{atom => any}, %{atom => any}) :: :ok
  def check_system_schema_version!(marker, context) do
    known_version = system_schema_version(context)

    if marker.system_schema_version > known_version do
      raise "the configured database's system tables are at layout version " <>
              "#{marker.system_schema_version}, from a newer Hologram - this Hologram knows " <>
              "layout versions up to #{known_version} - upgrade Hologram or point the config " <>
              "at another database"
    end

    :ok
  end

  @doc """
  Creates the control-plane bookkeeping tables in the hologram_system schema.
  """
  @spec create_system_tables() :: :ok
  def create_system_tables do
    Enum.each(system_statements(), fn statement ->
      {:ok, _result} = Connection.query(statement)
    end)

    :ok
  end

  @doc """
  Ensures the connected database is managed by schema reconciliation, claiming it when
  virgin - runs in the caller's transaction.

  A database containing neither Hologram schema is virgin (other schemas may exist -
  claiming touches nothing outside the two Hologram schemas): both schemas, the
  bookkeeping tables, and the marker are created, and :claimed is returned. A database
  whose marker matches the given context (:otp_app, :env, :hologram_version, and
  :timestamp - the latter two used when claiming) returns :managed. Every other state
  raises with a specific message: Hologram schemas without a marker, a marker belonging
  to another app or env, a database managed by migrations, or system tables at a newer
  layout than the running one (see system_schema_version/1, which reads the context's
  optional :system_upgrades). It never upgrades the system tables of a database it finds
  managed - that is upgrade_system_tables!/1, which reconcile/1 runs next in the same
  transaction. In the dev env, the messages of the states mix holo.db.reset clears name it:
  the Hologram schemas without a marker and the newer layout.
  """
  @spec ensure_managed!(%{atom => any}) :: :claimed | :managed
  def ensure_managed!(context) do
    data_schema = Mapper.data_schema()
    system_schema = Mapper.system_schema()

    case hologram_schemas() do
      [] -> claim(context)
      [^data_schema, ^system_schema] -> check_marker!(context)
      _partial -> raise_not_managed!(context)
    end
  end

  @doc """
  Logs one info line per given system table layout version, the versions
  upgrade_system_tables!/1 returned - called once its transaction has committed, so a line never
  names an upgrade that rolled back. Returns :ok.
  """
  @spec log_system_upgrades(list(pos_integer)) :: :ok
  def log_system_upgrades(versions) do
    Enum.each(versions, fn version ->
      Logger.info("Hologram: upgraded the system tables to layout version #{version}")
    end)
  end

  @doc """
  Returns the upgrade steps above the layout the connected database's marker records, in order -
  the ones upgrade_system_tables!/1 would run. The steps follow the context (see
  system_schema_version/1). The marker has to exist.
  """
  @spec pending_system_upgrades(%{atom => any}) :: list({pos_integer, list(String.t())})
  def pending_system_upgrades(context) do
    stored_version = read_marker().system_schema_version

    context
    |> system_upgrades()
    |> Enum.filter(fn {version, _statements} -> version > stored_version end)
  end

  @doc """
  Returns the managed-database marker, or nil when none has been written.

  The marker is a map with :otp_app, :env, and :managed_by (the guard facts, as
  strings) plus :hologram_version, :system_schema_version (the layout version of the
  hologram_system tables) and :last_reconciled_at (diagnostics). Schema reconciliation refreshes
  :hologram_version and :last_reconciled_at on every run - the migrator never does, so on a
  database it manages they are the claim's, whatever layout later upgrades brought.
  """
  @spec read_marker() :: %{atom => any} | nil
  def read_marker do
    statement = """
    SELECT "otp_app", "env", "managed_by", "hologram_version", "system_schema_version",
           "last_reconciled_at"
    FROM "#{Mapper.system_schema()}"."database"
    """

    {:ok, %{rows: rows}} = Connection.query(statement)

    case rows do
      [] ->
        nil

      [[otp_app, env, managed_by, hologram_version, system_schema_version, last_reconciled_at]] ->
        %{
          otp_app: otp_app,
          env: env,
          managed_by: managed_by,
          hologram_version: hologram_version,
          system_schema_version: system_schema_version,
          last_reconciled_at: last_reconciled_at
        }
    end
  end

  @doc """
  Converges the database schema to the given mapping and returns %{status:, ops:} -
  status is :claimed (virgin database) or :managed, ops are the applied change ops
  (empty when the schema already matched).

  The whole run is one crash-atomic transaction serialized by an advisory lock: guard
  check (claiming when virgin), upgrade the system tables to the running layout (see
  upgrade_system_tables!/1), introspect the actual schema, project the target from
  the mapping, diff, apply and register the renames the diff recognised (after an alien
  check of their own) and introspect again, alien check (dropping or renaming an object the
  registry does not know fails loudly - hologram_data is model-managed), pre-flight data
  validation (transformations the existing rows cannot follow fail with the ways out
  before any DDL runs), render and apply the DDL, update the managed-object registry from
  the op stream, and refresh the marker (last_reconciled_at, hologram_version). After the
  transaction commits, each system table upgrade, each destructive action and each join
  table rename is logged as one concise line. The context carries :mapping plus the guard
  facts (:otp_app, :env) and the marker diagnostics (:hologram_version, :timestamp), and
  optionally :plan, the indexes the model leaves to `Hologram.DB.IndexPlan` - the target
  holds them beside the model's own, and they go through the same diff, alien check and
  registry. Without one, the plan is the framework's own lookups'. It may also carry
  :system_upgrades, steps in place of system_schema_upgrades/0's (see
  system_schema_version/1).

  In the dev env, every refusal mix holo.db.reset clears names it: those of ensure_managed!/1
  that it clears, a failed system table upgrade, an alien object, a primary key edited by hand
  and a preflight refusal.
  """
  @spec reconcile(%{atom => any}) :: %{atom => any}
  def reconcile(context) do
    {:ok, {result, upgraded}} =
      Connection.transaction(fn ->
        {:ok, _result} =
          Connection.query("SELECT pg_advisory_xact_lock($1)", [@advisory_lock_key])

        status = ensure_managed!(context)
        {ops, upgraded} = with_reset_hint(context, fn -> converge!(context) end)

        {%{status: status, ops: ops}, upgraded}
      end)

    log_system_upgrades(upgraded)
    log_notable_ops(result.ops, context.mapping)

    result
  end

  @doc """
  Returns the managed-object registry as a set of {kind, parent, name} tuples - kind is
  one of :table, :column, :constraint, :index, or :enum_type, and parent is the owning
  table name (an empty string for standalone objects: tables and enum types).
  """
  @spec registry() :: MapSet.t()
  def registry do
    statement =
      ~s(SELECT "kind", "parent", "name" FROM "#{Mapper.system_schema()}"."schema_object")

    {:ok, %{rows: rows}} = Connection.query(statement)

    MapSet.new(rows, fn [kind, parent, name] ->
      {String.to_existing_atom(kind), parent, name}
    end)
  end

  @doc """
  Returns the hologram_system layout steps, in order, as {version, statements} - each step's
  version is the layout its statements produce, and the last one's is the running layout (see
  system_schema_version/1).

  Empty until a release after the data layer's first one changes a system table. Layout 1 is what
  the first release ships, and no database before it is carried forward: until then a change goes
  into the bookkeeping DDL alone, and a database claimed earlier is dropped and claimed again.

  After it, a release that changes the system tables adds one step, numbered one above the last,
  so the versions run 2, 3 and on. Step N brings layout N - 1 to N, and the same change goes into
  the bookkeeping DDL, so a claim builds the latest layout directly. The statements run in the
  boot's transaction (see upgrade_system_tables!/1), so none of them can be CONCURRENTLY, and a
  step's locks hold until the boot commits. And the marker table, with every column read_marker/0
  selects, stays readable at every layout in both directions: the marker is read before any step
  runs, and an earlier release reads it to refuse a newer layout.

  A step needn't keep the previous release's code working: old and new nodes serving one database
  at once isn't supported yet (#1627), so the previous release's nodes are stopped before this
  one boots. Once it is, steps have to be additive: new tables, and new columns that are nullable
  or have a default.
  """
  @spec system_schema_upgrades() :: list({pos_integer, list(String.t())})
  def system_schema_upgrades, do: []

  @doc """
  Returns the running layout version of the hologram_system tables: the last upgrade step's
  version, or 1 when there is none. The steps are the context's :system_upgrades when it carries
  one - a test's, standing in for a later release's - and system_schema_upgrades/0's otherwise.

  Every marker stores the version its database's tables are at, so a database states which layout
  it has: the alternative is introspecting the tables, which only works while the differences show
  in the catalog. An integer rather than the package version, so the check is a monotonic
  comparison, and a release that changes no system table leaves it alone. Derived from the steps
  rather than held beside them, so the two can't disagree.
  """
  @spec system_schema_version(%{atom => any}) :: pos_integer
  def system_schema_version(context) do
    last_step =
      context
      |> system_upgrades()
      |> List.last()

    case last_step do
      nil -> 1
      {version, _statements} -> version
    end
  end

  @doc """
  Applies the given change ops to the managed-object registry, in the caller's
  transaction.

  Create and add ops register the objects they produce (a created table registers
  itself, its columns, and its primary key constraint) - drop ops deregister them (a
  dropped table takes everything parented to it) - a constraint, index or enum type
  rename updates the registered name, and a table rename renames the table's row and
  re-parents every row under it. Ops that change an object without changing its identity
  (column alterations, enum value changes, rebuilds) leave the registry untouched.
  Registration is idempotent - stale rows from out-of-contract edits never fail it.
  """
  @spec update_registry(list(%{atom => any})) :: :ok
  def update_registry(ops) do
    Enum.each(ops, &record_op/1)
  end

  @doc """
  Carries the connected database's hologram_system tables to the running layout, in the caller's
  transaction: runs each pending step's statements in order (see pending_system_upgrades/1) and
  records the step's version in the marker. Returns the versions applied, for
  log_system_upgrades/1 once the transaction commits - empty for a database at the running
  layout. A statement the database refuses raises, naming the step's version, and the caller's
  transaction rolls the whole upgrade back.

  The caller holds a lock no other boot can hold beside it - reconcile/1's advisory lock, the
  migrator's migration lock - so a node that saw a pending step before the lock finds it done
  inside, and no step runs twice.
  """
  @spec upgrade_system_tables!(%{atom => any}) :: list(pos_integer)
  def upgrade_system_tables!(context) do
    statement = ~s(UPDATE "#{Mapper.system_schema()}"."database" SET "system_schema_version" = $1)

    context
    |> pending_system_upgrades()
    |> Enum.map(fn {version, statements} ->
      Enum.each(statements, &execute_upgrade_statement!(&1, version))
      {:ok, _result} = Connection.query(statement, [version])

      version
    end)
  end

  @doc """
  Writes the given marker as the single row of the managed-database marker table,
  replacing any previous row.

  The marker's system_schema_version is the layout the database has, so only a claim, which
  builds the tables at the running layout, writes one here - an upgrade step records its own
  (see upgrade_system_tables!/1), and a reconciliation refreshes the rest and leaves it alone.
  """
  @spec write_marker(%{atom => any}) :: :ok
  def write_marker(marker) do
    system_schema = Mapper.system_schema()

    {:ok, _result} = Connection.query(~s(DELETE FROM "#{system_schema}"."database"))

    insert_statement = """
    INSERT INTO "#{system_schema}"."database"
      ("otp_app", "env", "managed_by", "hologram_version", "system_schema_version",
       "last_reconciled_at")
    VALUES ($1, $2, $3, $4, $5, $6)
    """

    params = [
      marker.otp_app,
      marker.env,
      marker.managed_by,
      marker.hologram_version,
      marker.system_schema_version,
      marker.last_reconciled_at
    ]

    {:ok, _result} = Connection.query(insert_statement, params)

    :ok
  end

  # A required add with a declared default applies as add-nullable, parameterized fill,
  # then tighten - so existing rows receive the default and the DDL never carries values.
  defp apply_op(%{op: :add_column} = op, mapping) do
    fill =
      if op.definition.null, do: :none, else: Preflight.fill_value(mapping, op.table, op.column)

    case fill do
      :none ->
        execute_statements(DDL.statements(op))

      {:ok, encoded_value} ->
        nullable_definition = %{op.definition | null: true}
        execute_statements(DDL.statements(%{op | definition: nullable_definition}))
        fill_column(op.table, op.column, encoded_value)

        tighten_op = %{
          op: :alter_column,
          table: op.table,
          column: op.column,
          before: nullable_definition,
          after: op.definition
        }

        execute_statements(DDL.statements(tighten_op))
    end
  end

  # Pure null-tightening with a declared default fills the NULLs first - a combined
  # type change never fills (the default holds a new-type value, the column still has
  # the old type), so pre-flight lets only NULL-free combined changes through.
  defp apply_op(%{op: :alter_column} = op, mapping) do
    # A type change can convert two values to one, so it asks about the unique indexes
    # standing over the column right before it applies.
    Preflight.check_cast!(op)

    fill =
      if op.before.null and not op.after.null and op.before.type == op.after.type do
        Preflight.fill_value(mapping, op.table, op.column)
      else
        :none
      end

    case fill do
      :none ->
        :ok

      # Asked before the fill: under a unique index that stands, a fill making rows repeat a
      # key would fail in PostgreSQL.
      {:ok, encoded_value} ->
        Preflight.check_fill!(mapping, op.table, op.column, encoded_value)
        fill_column(op.table, op.column, encoded_value)

        # The filled rows held no value, so their companions are NULL too - and a string's
        # equality reads its sort key, so a row left without one would match no `==`.
        backfill_companions_of!(mapping, op.table, op.column)
    end

    execute_statements(DDL.statements(op))
  end

  # Asked again here, with the run's added columns in place: one filled with its default can
  # make rows repeat a key the preflight could not ask about. A tightening fill is asked about
  # before it runs (see Preflight.check_fill!/4).
  defp apply_op(%{op: :create_index, unique: true} = op, _mapping) do
    Preflight.check_unique_index!(op)

    execute_statements(DDL.statements(op))
  end

  defp apply_op(op, _mapping), do: execute_statements(DDL.statements(op))

  # The indexes the model leaves to the plan, which the context carries (see
  # Hologram.DB.reconciliation_context/0) - or, for a context built without one, as the tests
  # build theirs, the ones the framework's own lookups need.
  defp index_plan(%{plan: plan}), do: plan

  defp index_plan(context), do: IndexPlan.framework_plan(context.mapping)

  defp apply_ops(ops, mapping) do
    Enum.each(ops, &apply_op(&1, mapping))
  end

  # The row locks serialize the fill against concurrent entity updates - a live-reload
  # fill runs while the endpoint serves, and an update slipping between the read and the
  # companion write would get its fresh companion value overwritten from the stale read.
  # sobelow_skip ["SQL.Query"]
  defp backfill_companion!(table, companion_name, source_name, derive) do
    select_sql =
      ~s(SELECT "id", #{Mapper.quote_identifier(source_name)} FROM #{qualified_table(table)} FOR UPDATE)

    update_sql =
      ~s(UPDATE #{qualified_table(table)} SET #{Mapper.quote_identifier(companion_name)} = $1 WHERE "id" = $2)

    {:ok, %{rows: rows}} = Connection.query(select_sql, [])

    Enum.each(rows, fn
      [_id, nil] ->
        :ok

      [id, value] ->
        {:ok, _result} = Connection.query(update_sql, [derive.(value), id])
    end)
  end

  defp backfill_companions_of!(mapping, table, source_name) do
    {_entity_type, entity_mapping} =
      Enum.find(mapping, fn {_entity_type, table_mapping} -> table_mapping.table == table end)

    entity_mapping.columns
    |> Enum.filter(&Mapper.derived?/1)
    |> Enum.each(fn %{source: {_kind, attribute_name}} = companion ->
      if Enum.any?(
           entity_mapping.columns,
           &(&1.name == source_name and &1.source == {:attribute, attribute_name})
         ) do
        backfill_op!(%{table: table, column: companion.name}, mapping)
      end
    end)
  end

  defp backfill_op!(op, mapping) do
    {_entity_type, entity_mapping} =
      Enum.find(mapping, fn {_entity_type, table_mapping} -> table_mapping.table == op.table end)

    column = Enum.find(entity_mapping.columns, &(&1.name == op.column))

    case column do
      %{source: {kind, attribute_name}} when kind in [:search_key, :sort_key] ->
        source_column =
          Enum.find(entity_mapping.columns, &(&1.source == {:attribute, attribute_name}))

        derive = if kind == :sort_key, do: &SortKey.compute/1, else: &SortKey.search_key/1

        backfill_companion!(entity_mapping.table, column.name, source_column.name, derive)

      _other_column ->
        :ok
    end
  end

  defp check_alien!(%{op: :drop_column} = op, registry) do
    if {:column, op.table, op.column} not in registry do
      raise_alien!(~s(column "#{op.column}" on table "#{op.table}"))
    end
  end

  defp check_alien!(%{op: :drop_enum_type} = op, registry) do
    if {:enum_type, "", op.enum_type} not in registry do
      raise_alien!(~s(enum type "#{op.enum_type}"))
    end
  end

  defp check_alien!(%{op: :drop_foreign_key} = op, registry) do
    if {:constraint, op.table, op.constraint} not in registry do
      raise_alien!(~s(constraint "#{op.constraint}" on table "#{op.table}"))
    end
  end

  defp check_alien!(%{op: :drop_index} = op, registry) do
    index = op.index

    if not Enum.any?(registry, &match?({:index, _parent, ^index}, &1)) do
      raise_alien!(~s(index "#{op.index}"))
    end
  end

  defp check_alien!(%{op: :drop_table} = op, registry) do
    if {:table, "", op.table} not in registry do
      raise_alien!(~s(table "#{op.table}"))
    end
  end

  # Renaming an object the registry doesn't know would adopt it under a derived name - an index,
  # a join-shaped table or an enum type made by hand that the model happens to match - so it
  # raises as its drop would.
  defp check_alien!(%{op: :rename_enum_type} = op, registry) do
    check_alien!(%{op: :drop_enum_type, enum_type: op.from}, registry)
  end

  defp check_alien!(%{op: :rename_index} = op, registry) do
    check_alien!(%{op: :drop_index, index: op.from}, registry)
  end

  defp check_alien!(%{op: :rename_table} = op, registry) do
    check_alien!(%{op: :drop_table, table: op.from}, registry)
  end

  defp check_alien!(_op, _registry), do: :ok

  defp check_aliens!(ops, registry) do
    Enum.each(ops, &check_alien!(&1, registry))
  end

  defp check_marker!(context) do
    if not marker_table_exists?() do
      raise_not_managed!(context)
    end

    marker = read_marker()

    cond do
      marker == nil ->
        raise_not_managed!(context)

      marker.otp_app != context.otp_app ->
        raise "the configured database belongs to app \"#{marker.otp_app}\" - " <>
                "the current app is \"#{context.otp_app}\" - " <>
                "point the config at the right database"

      marker.env != context.env ->
        raise "the configured database belongs to the \"#{marker.env}\" env - " <>
                "the current env is \"#{context.env}\" - " <>
                "the config points at another env's database"

      marker.managed_by != "reconciliation" ->
        raise "the configured database is managed by #{marker.managed_by} - " <>
                "schema reconciliation never touches it"

      true ->
        with_reset_hint(context, fn -> check_system_schema_version!(marker, context) end)
        :managed
    end
  end

  defp claim(context) do
    {:ok, _result} = Connection.query(~s(CREATE SCHEMA "#{Mapper.system_schema()}"))
    {:ok, _result} = Connection.query(~s(CREATE SCHEMA "#{Mapper.data_schema()}"))

    create_system_tables()

    write_marker(%{
      otp_app: context.otp_app,
      env: context.env,
      managed_by: "reconciliation",
      hologram_version: context.hologram_version,
      system_schema_version: system_schema_version(context),
      last_reconciled_at: context.timestamp
    })

    :claimed
  end

  # Everything past the guard: upgrade the system tables, then converge hologram_data to the
  # mapping. Returns the applied ops and the system table versions upgraded to.
  defp converge!(context) do
    upgraded = upgrade_system_tables!(context)

    actual = Introspection.schema()
    target = Schema.from_mapping(context.mapping, index_plan(context))

    {renames, changes} =
      actual
      |> Schema.diff(target)
      |> Enum.split_with(&(&1.op in @rename_ops))

    # The renames apply and register first, so the alien check and the preflight below see the
    # database and the registry as the renames leave them - the changes name objects by their
    # target names. A preflight refusal still rolls the renames back.
    check_aliens!(renames, registry())
    apply_ops(renames, context.mapping)
    update_registry(renames)

    renamed = if renames == [], do: actual, else: Introspection.schema()

    check_aliens!(changes, registry())
    Preflight.run!(changes, renamed, context.mapping)

    apply_ops(changes, context.mapping)

    # A companion this run adds is filled AFTER every op has applied, not at its own add: the
    # diff applies add_column before alter_column, so a source column being cast to text in the
    # same run still holds its old type when its companion lands.
    backfill_companions!(changes, context.mapping)

    update_registry(changes)
    refresh_marker(context)

    {renames ++ changes, upgraded}
  end

  defp deregister(kind, parent, name) do
    statement = """
    DELETE FROM "#{Mapper.system_schema()}"."schema_object"
    WHERE "kind" = $1 AND "parent" = $2 AND "name" = $3
    """

    {:ok, _result} = Connection.query(statement, [Atom.to_string(kind), parent, name])

    :ok
  end

  defp execute_statements(statements) do
    Enum.each(statements, fn statement ->
      {:ok, _result} = Connection.query(statement)
    end)
  end

  defp execute_upgrade_statement!(statement, version) do
    case Connection.query(statement) do
      {:ok, _result} ->
        :ok

      {:error, error} ->
        raise "upgrading the system tables to layout version #{version} failed - " <>
                Exception.message(error)
    end
  end

  defp fill_column(table, column, encoded_value) do
    fill_statement = DDL.fill_statement(table, column)

    {:ok, _result} = Connection.query(fill_statement, [encoded_value])
  end

  defp hologram_schemas do
    statement = """
    SELECT nspname
    FROM pg_catalog.pg_namespace
    WHERE nspname IN ('#{Mapper.data_schema()}', '#{Mapper.system_schema()}')
    ORDER BY nspname
    """

    {:ok, %{rows: rows}} = Connection.query(statement)

    Enum.map(rows, fn [name] -> name end)
  end

  defp log_notable_op(%{op: :drop_column} = op, _mapping) do
    Logger.warning(
      ~s(Hologram: schema reconciliation dropped column "#{op.column}" on table "#{op.table}")
    )
  end

  defp log_notable_op(%{op: :drop_enum_type} = op, _mapping) do
    Logger.warning(~s(Hologram: schema reconciliation dropped enum type "#{op.enum_type}"))
  end

  defp log_notable_op(%{op: :drop_table} = op, _mapping) do
    Logger.warning(~s(Hologram: schema reconciliation dropped table "#{op.table}"))
  end

  defp log_notable_op(%{op: :rebuild_enum_type} = op, _mapping) do
    Logger.warning(~s(Hologram: schema reconciliation rebuilt enum type "#{op.enum_type}"))
  end

  # A join table rename is a guess - the pairing can't tell a renamed relationship from one
  # deleted and another added between the same two tables - so it is logged like the drops,
  # naming the relationship that now holds the links.
  defp log_notable_op(%{op: :rename_table} = op, mapping) do
    {entity_type, relationship} =
      Enum.find_value(mapping, fn {entity_type, entity_mapping} ->
        Enum.find_value(entity_mapping.join_tables, fn join_table ->
          join_table.name == op.to && {entity_type, join_table.relationship}
        end)
      end)

    Logger.warning(
      ~s(Hologram: schema reconciliation renamed join table "#{op.from}" to "#{op.to}", ) <>
        "keeping its links. If relationship #{inspect(relationship)} of #{inspect(entity_type)} " <>
        "is a new relationship, not a rename, delete its links or reset the database"
    )
  end

  defp log_notable_op(_op, _mapping), do: :ok

  defp log_notable_ops(ops, mapping) do
    Enum.each(ops, &log_notable_op(&1, mapping))
  end

  defp marker_table_exists? do
    statement = """
    SELECT 1
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = '#{Mapper.system_schema()}' AND c.relname = 'database' AND c.relkind = 'r'
    """

    {:ok, %{rows: rows}} = Connection.query(statement)

    rows != []
  end

  defp raise_alien!(description) do
    raise "unknown #{description} in the #{Mapper.data_schema()} schema - " <>
            "this schema is model-managed - " <>
            "move the object to another schema or remove it"
  end

  defp raise_not_managed!(context) do
    with_reset_hint(context, fn ->
      raise "the configured database contains Hologram schemas but no managed-database " <>
              "marker - it is not managed by schema reconciliation - drop the " <>
              ~s("#{Mapper.system_schema()}" and "#{Mapper.data_schema()}" schemas or point the config ) <>
              "at another database"
    end)
  end

  # The guard facts already match - ensure_managed!/1 checked them - and the layout version is
  # left to the claim and the upgrade steps: a refresh records when the database was last
  # reconciled and by which Hologram, not the layout the code expects.
  defp refresh_marker(context) do
    statement = """
    UPDATE "#{Mapper.system_schema()}"."database"
    SET "hologram_version" = $1, "last_reconciled_at" = $2
    """

    {:ok, _result} = Connection.query(statement, [context.hologram_version, context.timestamp])

    :ok
  end

  defp qualified_table(table) do
    ~s("#{Mapper.data_schema()}".#{Mapper.quote_identifier(table)})
  end

  defp record_op(%{op: :add_column} = op), do: register(:column, op.table, op.column)

  defp record_op(%{op: :add_enum_value}), do: :ok

  defp record_op(%{op: :add_foreign_key} = op), do: register(:constraint, op.table, op.constraint)

  defp record_op(%{op: :alter_column}), do: :ok

  defp record_op(%{op: :create_enum_type} = op), do: register(:enum_type, "", op.enum_type)

  defp record_op(%{op: :create_index} = op), do: register(:index, op.table, op.index)

  defp record_op(%{op: :create_table} = op) do
    register(:table, "", op.table)

    op.columns
    |> Map.keys()
    |> Enum.each(&register(:column, op.table, &1))

    register(:constraint, op.table, op.primary_key.constraint)
  end

  defp record_op(%{op: :drop_column} = op), do: deregister(:column, op.table, op.column)

  defp record_op(%{op: :drop_enum_type} = op), do: deregister(:enum_type, "", op.enum_type)

  defp record_op(%{op: :drop_foreign_key} = op) do
    deregister(:constraint, op.table, op.constraint)
  end

  defp record_op(%{op: :drop_index} = op) do
    statement = """
    DELETE FROM "#{Mapper.system_schema()}"."schema_object"
    WHERE "kind" = 'index' AND "name" = $1
    """

    {:ok, _result} = Connection.query(statement, [op.index])

    :ok
  end

  defp record_op(%{op: :drop_table} = op) do
    statement = """
    DELETE FROM "#{Mapper.system_schema()}"."schema_object"
    WHERE ("kind" = 'table' AND "name" = $1) OR "parent" = $1
    """

    {:ok, _result} = Connection.query(statement, [op.table])

    :ok
  end

  defp record_op(%{op: :rebuild_enum_type}), do: :ok

  defp record_op(%{op: :rename_constraint} = op) do
    statement = """
    UPDATE "#{Mapper.system_schema()}"."schema_object"
    SET "name" = $1
    WHERE "kind" = 'constraint' AND "parent" = $2 AND "name" = $3
    """

    {:ok, _result} = Connection.query(statement, [op.to, op.table, op.from])

    :ok
  end

  # A stale row under the new name goes first, so registration stays idempotent.
  defp record_op(%{op: :rename_enum_type} = op) do
    statement = """
    DELETE FROM "#{Mapper.system_schema()}"."schema_object"
    WHERE "kind" = 'enum_type' AND "parent" = '' AND "name" IN ($1, $2)
    """

    {:ok, _result} = Connection.query(statement, [op.from, op.to])

    register(:enum_type, "", op.to)
  end

  defp record_op(%{op: :rename_enum_value}), do: :ok

  # By name alone, the way the alien check found it and a drop deregisters it: index names are
  # unique in the data schema, whatever parent a row states. Every row under either name goes,
  # stale ones included, and the index registers again under its new name and table - so
  # registration stays idempotent.
  defp record_op(%{op: :rename_index} = op) do
    statement = """
    DELETE FROM "#{Mapper.system_schema()}"."schema_object"
    WHERE "kind" = 'index' AND "name" IN ($1, $2)
    """

    {:ok, _result} = Connection.query(statement, [op.from, op.to])

    register(:index, op.table, op.to)
  end

  # The table's own row, and the parent of every row under it - its columns, constraints and
  # indexes move with it. Stale rows under the new name go first, so registration stays
  # idempotent.
  defp record_op(%{op: :rename_table} = op) do
    system_schema = Mapper.system_schema()

    stale_statement = """
    DELETE FROM "#{system_schema}"."schema_object"
    WHERE ("kind" = 'table' AND "parent" = '' AND "name" = $1) OR "parent" = $1
    """

    table_statement = """
    UPDATE "#{system_schema}"."schema_object"
    SET "name" = $1
    WHERE "kind" = 'table' AND "parent" = '' AND "name" = $2
    """

    children_statement = """
    UPDATE "#{system_schema}"."schema_object"
    SET "parent" = $1
    WHERE "parent" = $2
    """

    {:ok, _result} = Connection.query(stale_statement, [op.to])
    {:ok, _result} = Connection.query(table_statement, [op.to, op.from])
    {:ok, _result} = Connection.query(children_statement, [op.to, op.from])

    :ok
  end

  defp register(kind, parent, name) do
    statement = """
    INSERT INTO "#{Mapper.system_schema()}"."schema_object" ("kind", "parent", "name")
    VALUES ($1, $2, $3)
    ON CONFLICT DO NOTHING
    """

    {:ok, _result} = Connection.query(statement, [Atom.to_string(kind), parent, name])

    :ok
  end

  # Control-plane bookkeeping DDL - static and framework-owned, never model-derived. A change to
  # it takes an upgrade step once the data layer has shipped, and none before - see
  # system_schema_upgrades/0.
  #
  # The database table is the managed-database marker (single row, written by write_marker/1 at
  # the claim and refreshed by each reconciliation) - the schema_object table is the
  # managed-object registry - the migration table records the applied migration versions - the
  # oplog table records the effect each write had, written in the writing transaction and read by
  # the dispatcher -
  # the mutation table records each batch of client writes the server ANSWERED, by the
  # client that sent it and that client's sequence number, which is what answers a batch
  # arriving twice - and keeps a refused batch as it arrived, since its rows reached no log.
  #
  # The envelope column is filled for a refused batch only. A batch that LANDED has its rows
  # in the oplog under mutation_ref, keyed by the same pair, so keeping them here would keep
  # every write twice - a refused batch's rows are nowhere else, which is what this column is
  # for. A refused batch's claim rolls back with its transaction, and its row is written
  # afterwards, on its own statement.
  #
  # The oplog is read by transaction id rather than by insert order, because a sequence
  # hands out its numbers before the transaction holding them commits: a reader trusting
  # seq order would pass a row whose transaction is still open and never come back for it.
  # Hence the tx column, defaulted to the writing transaction's own id, and the index the
  # windowed read walks.
  #
  # The oplog's old column holds what the to-one references an update changed held before it,
  # which is what points sync at the rows a move took a row away from. It is NULL for an update
  # that changed no reference and for every other effect: a put has no before, a delete keeps the
  # whole row in data, and an edge names both ends.
  #
  # The second oplog index is BRIN rather than btree, and pruning is what reads it. The
  # table is append-only, so inserted_at runs with the physical order of the pages, which
  # is the one case BRIN is built for: kilobytes of index instead of gigabytes, and no
  # per-row tree descent on a table every entity write appends to. A btree here would put
  # its rightmost page in the path of every write in the system to speed up an hourly
  # chore.
  #
  # Every environment gets the same tables, and which of them a database uses follows
  # from how it is managed: reconciliation writes the registry and never the migration
  # table, the migration applier the other way around. One schema everywhere keeps
  # existence checks and the framework's own system-table evolution uniform.
  defp system_statements do
    system_schema = Mapper.system_schema()

    [
      """
      CREATE TABLE "#{system_schema}"."database" (
        "otp_app" text NOT NULL,
        "env" text NOT NULL,
        "managed_by" text NOT NULL,
        "hologram_version" text NOT NULL,
        "system_schema_version" integer NOT NULL,
        "last_reconciled_at" timestamptz NOT NULL
      )
      """,
      """
      CREATE TABLE "#{system_schema}"."migration" (
        "version" text NOT NULL,
        "applied_at" timestamptz NOT NULL,
        "model_hash" text NOT NULL,
        PRIMARY KEY ("version")
      )
      """,
      """
      CREATE TABLE "#{system_schema}"."oplog" (
        "seq" bigserial PRIMARY KEY,
        "op" text NOT NULL,
        "type" text NOT NULL,
        "entity_id" uuid NOT NULL,
        "data" jsonb,
        "tx" xid8 NOT NULL DEFAULT pg_current_xact_id(),
        "model_hash" text NOT NULL,
        "mutation_ref" jsonb,
        "revisions" jsonb,
        "old" jsonb,
        "actor_id" uuid,
        "inserted_at" timestamptz NOT NULL DEFAULT now()
      )
      """,
      """
      CREATE INDEX "oplog_tx_seq_$idx" ON "#{system_schema}"."oplog" ("tx", "seq")
      """,
      """
      CREATE INDEX "oplog_inserted_at_$idx" ON "#{system_schema}"."oplog"
      USING brin ("inserted_at")
      """,
      """
      CREATE TABLE "#{system_schema}"."mutation" (
        "replica_id" text NOT NULL,
        "seq" bigint NOT NULL,
        "actor_id" uuid,
        "model_hash" text NOT NULL,
        "result" jsonb,
        "envelope" jsonb,
        "answered_at" timestamptz NOT NULL DEFAULT now(),
        PRIMARY KEY ("replica_id", "seq")
      )
      """,
      """
      CREATE TABLE "#{system_schema}"."schema_object" (
        "kind" text NOT NULL,
        "parent" text NOT NULL,
        "name" text NOT NULL,
        PRIMARY KEY ("kind", "parent", "name")
      )
      """
    ]
  end

  defp system_upgrades(context) do
    Map.get(context, :system_upgrades, system_schema_upgrades())
  end

  # RuntimeError only: the refusals raise it, and an error of another kind, like a failed match
  # on a statement's result, is a Hologram bug the reset is no way out of.
  defp with_reset_hint(%{env: "dev"}, fun) do
    fun.()
  rescue
    error in RuntimeError ->
      reraise RuntimeError, [message: error.message <> @reset_hint], __STACKTRACE__
  end

  defp with_reset_hint(_context, fun), do: fun.()
end
