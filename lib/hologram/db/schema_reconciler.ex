defmodule Hologram.DB.SchemaReconciler do
  @moduledoc false

  require Logger

  alias Hologram.DB.Connection
  alias Hologram.DB.DDL
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

  # The layout version of the hologram_system tables themselves - bumped when the
  # bookkeeping DDL below or the marker's columns change, ONCE PER RELEASE rather than once
  # per change. Stamped into every marker so a database states which layout it was built
  # with: the alternative is introspecting the tables to find out, which only works while
  # the differences are visible in the catalog. An integer rather than the package version,
  # so the check is a monotonic comparison rather than version-string parsing, and a release
  # that changes nothing here leaves it alone.
  #
  # STILL 1 while the data layer is unreleased, deliberately. The outbox table, its two
  # indexes and the migration table's model_hash column all arrived after this number was
  # first set, and none of them has shipped: `lib/hologram/db` exists on neither master nor
  # dev, and the published package has no data layer at all. A version names a layout
  # someone can be RUNNING, so numbering the intermediate states of an unreleased branch
  # would invent layouts no database was ever built with.
  #
  # Owed at the data layer's first release, and both halves are owed together: bump this
  # once for the whole arc, and add the upgrade that carries an already-claimed database to
  # it. `create_system_tables/0` runs only when claiming a virgin database, so a claimed one
  # never gains a later table or column on its own - the symptom is not subtle, and it has
  # been seen: a database claimed before the outbox existed makes every dispatcher poll
  # crash with `relation "hologram_system.outbox" does not exist`. Harmless only because no
  # such database exists outside this branch's local dev and test databases and CI's, which
  # are virgin per run - and until that upgrade exists a stale one is dropped and recreated
  # rather than carried forward.
  @system_schema_version 1

  # Control-plane bookkeeping DDL - static and framework-owned, never model-derived.
  # The database table is the managed-database marker (single row, maintained by
  # write_marker/1) - the schema_object table is the managed-object registry - the
  # migration table records the applied migration versions - the outbox table records the
  # effect each write had, written in the writing transaction and read by the dispatcher.
  #
  # The outbox is read by transaction id rather than by insert order, because a sequence
  # hands out its numbers before the transaction holding them commits: a reader trusting
  # seq order would pass a row whose transaction is still open and never come back for it.
  # Hence the tx column, defaulted to the writing transaction's own id, and the index the
  # windowed read walks.
  #
  # The second outbox index is BRIN rather than btree, and pruning is what reads it. The
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
  @system_statements [
    """
    CREATE TABLE "hologram_system"."database" (
      "otp_app" text NOT NULL,
      "env" text NOT NULL,
      "managed_by" text NOT NULL,
      "hologram_version" text NOT NULL,
      "system_schema_version" integer NOT NULL,
      "last_reconciled_at" timestamptz NOT NULL
    )
    """,
    """
    CREATE TABLE "hologram_system"."migration" (
      "version" text NOT NULL,
      "applied_at" timestamptz NOT NULL,
      "model_hash" text NOT NULL,
      PRIMARY KEY ("version")
    )
    """,
    """
    CREATE TABLE "hologram_system"."outbox" (
      "seq" bigserial PRIMARY KEY,
      "op" text NOT NULL,
      "type" text NOT NULL,
      "entity_id" uuid NOT NULL,
      "data" jsonb,
      "tx" xid8 NOT NULL DEFAULT pg_current_xact_id(),
      "model_hash" text NOT NULL,
      "mutation_ref" jsonb,
      "actor_id" uuid,
      "inserted_at" timestamptz NOT NULL DEFAULT now()
    )
    """,
    """
    CREATE INDEX "outbox_tx_seq_$idx" ON "hologram_system"."outbox" ("tx", "seq")
    """,
    """
    CREATE INDEX "outbox_inserted_at_$idx" ON "hologram_system"."outbox"
    USING brin ("inserted_at")
    """,
    """
    CREATE TABLE "hologram_system"."schema_object" (
      "kind" text NOT NULL,
      "parent" text NOT NULL,
      "name" text NOT NULL,
      PRIMARY KEY ("kind", "parent", "name")
    )
    """
  ]

  @doc """
  Fills every sort-key companion column the given ops add, from the companion's source
  column, one row at a time in the caller's transaction - the key of a nil value is nil.
  Ops adding no companion are passed over. Returns :ok.
  """
  @spec backfill_sort_keys!(list(%{atom => any}), %{module => %{atom => any}}) :: :ok
  def backfill_sort_keys!(ops, mapping) do
    ops
    |> Enum.filter(&match?(%{op: :add_column}, &1))
    |> Enum.each(&backfill_op!(&1, mapping))
  end

  @doc """
  Creates the control-plane bookkeeping tables in the hologram_system schema.
  """
  @spec create_system_tables() :: :ok
  def create_system_tables do
    Enum.each(@system_statements, fn statement ->
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
  to another app or env, or a database managed by migrations.
  """
  @spec ensure_managed!(%{atom => any}) :: :claimed | :managed
  def ensure_managed!(context) do
    case hologram_schemas() do
      [] -> claim(context)
      ["hologram_data", "hologram_system"] -> check_marker!(context)
      _partial -> raise_not_managed!()
    end
  end

  @doc """
  Returns the managed-database marker, or nil when none has been written.

  The marker is a map with :otp_app, :env, and :managed_by (the guard facts, as
  strings) plus :hologram_version, :system_schema_version (the layout version of the
  hologram_system tables) and :last_reconciled_at (diagnostics).
  """
  @spec read_marker() :: %{atom => any} | nil
  def read_marker do
    statement = """
    SELECT "otp_app", "env", "managed_by", "hologram_version", "system_schema_version",
           "last_reconciled_at"
    FROM "hologram_system"."database"
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
  check (claiming when virgin), introspect the actual schema, project the target from
  the mapping, diff, alien check (dropping an object the registry does not know fails
  loudly - hologram_data is model-managed), pre-flight data validation (transformations
  the existing rows cannot follow fail with the ways out before any DDL runs), render
  and apply the DDL, update the managed-object registry from the op stream, and refresh
  the marker (last_reconciled_at, hologram_version). After the transaction commits,
  each destructive action is logged as one concise line. The context carries :mapping
  plus the guard facts (:otp_app, :env) and the marker diagnostics (:hologram_version,
  :timestamp).
  """
  @spec reconcile(%{atom => any}) :: %{atom => any}
  def reconcile(context) do
    {:ok, result} =
      Connection.transaction(fn ->
        {:ok, _result} =
          Connection.query("SELECT pg_advisory_xact_lock($1)", [@advisory_lock_key])

        status = ensure_managed!(context)

        actual = Introspection.schema()
        target = Schema.from_mapping(context.mapping)
        ops = Schema.diff(actual, target)

        check_aliens!(ops, registry())
        Preflight.run!(ops, actual, context.mapping)

        apply_ops(ops, context.mapping)

        # A companion this run adds is filled AFTER every op has applied, not at its own
        # add: the diff applies add_column before alter_column, so a source column being
        # cast to text in the same run still holds its old type when its companion lands.
        backfill_sort_keys!(ops, context.mapping)

        update_registry(ops)
        write_marker(marker_from_context(context))

        %{status: status, ops: ops}
      end)

    log_destructive_ops(result.ops)

    result
  end

  @doc """
  Returns the managed-object registry as a set of {kind, parent, name} tuples - kind is
  one of :table, :column, :constraint, :index, or :enum_type, and parent is the owning
  table name (an empty string for standalone objects: tables and enum types).
  """
  @spec registry() :: MapSet.t()
  def registry do
    statement = ~s(SELECT "kind", "parent", "name" FROM "hologram_system"."schema_object")

    {:ok, %{rows: rows}} = Connection.query(statement)

    MapSet.new(rows, fn [kind, parent, name] ->
      {String.to_existing_atom(kind), parent, name}
    end)
  end

  @doc """
  Applies the given change ops to the managed-object registry, in the caller's
  transaction.

  Create and add ops register the objects they produce (a created table registers
  itself, its columns, and its primary key constraint) - drop ops deregister them (a
  dropped table takes everything parented to it) - a constraint rename updates the
  registered name. Ops that change an object without changing its identity (column
  alterations, enum value changes, rebuilds) leave the registry untouched.
  Registration is idempotent - stale rows from out-of-contract edits never fail it.
  """
  @spec update_registry(list(%{atom => any})) :: :ok
  def update_registry(ops) do
    Enum.each(ops, &record_op/1)
  end

  @doc """
  Writes the given marker as the single row of the managed-database marker table,
  replacing any previous row.

  The system schema layout version is the writer's own, not the caller's - the caller
  states what it knows about the app, and the layout is a fact about the code doing the
  writing.
  """
  @spec write_marker(%{atom => any}) :: :ok
  def write_marker(marker) do
    {:ok, _result} = Connection.query(~s(DELETE FROM "hologram_system"."database"))

    insert_statement = """
    INSERT INTO "hologram_system"."database"
      ("otp_app", "env", "managed_by", "hologram_version", "system_schema_version",
       "last_reconciled_at")
    VALUES ($1, $2, $3, $4, $5, $6)
    """

    params = [
      marker.otp_app,
      marker.env,
      marker.managed_by,
      marker.hologram_version,
      @system_schema_version,
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
    fill =
      if op.before.null and not op.after.null and op.before.type == op.after.type do
        Preflight.fill_value(mapping, op.table, op.column)
      else
        :none
      end

    case fill do
      :none -> :ok
      {:ok, encoded_value} -> fill_column(op.table, op.column, encoded_value)
    end

    execute_statements(DDL.statements(op))
  end

  defp apply_op(op, _mapping), do: execute_statements(DDL.statements(op))

  defp apply_ops(ops, mapping) do
    Enum.each(ops, &apply_op(&1, mapping))
  end

  # The row locks serialize the fill against concurrent entity updates - a live-reload
  # fill runs while the endpoint serves, and an update slipping between the read and the
  # companion write would get its fresh companion value overwritten from the stale read.
  # sobelow_skip ["SQL.Query"]
  defp backfill_sort_key!(table, companion_name, source_name) do
    select_sql =
      ~s(SELECT "id", #{Mapper.quote_identifier(source_name)} FROM #{qualified_table(table)} FOR UPDATE)

    update_sql =
      ~s(UPDATE #{qualified_table(table)} SET #{Mapper.quote_identifier(companion_name)} = $1 WHERE "id" = $2)

    {:ok, %{rows: rows}} = Connection.query(select_sql, [])

    Enum.each(rows, fn
      [_id, nil] ->
        :ok

      [id, value] ->
        {:ok, _result} = Connection.query(update_sql, [SortKey.compute(value), id])
    end)
  end

  defp backfill_op!(op, mapping) do
    {_entity_type, entity_mapping} =
      Enum.find(mapping, fn {_entity_type, table_mapping} -> table_mapping.table == op.table end)

    column = Enum.find(entity_mapping.columns, &(&1.name == op.column))

    case column do
      %{source: {:sort_key, attribute_name}} ->
        source_column =
          Enum.find(entity_mapping.columns, &(&1.source == {:attribute, attribute_name}))

        backfill_sort_key!(entity_mapping.table, column.name, source_column.name)

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

  defp check_alien!(_op, _registry), do: :ok

  defp check_aliens!(ops, registry) do
    Enum.each(ops, &check_alien!(&1, registry))
  end

  defp check_marker!(context) do
    if not marker_table_exists?() do
      raise_not_managed!()
    end

    marker = read_marker()

    cond do
      marker == nil ->
        raise_not_managed!()

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
        :managed
    end
  end

  defp claim(context) do
    {:ok, _result} = Connection.query(~s(CREATE SCHEMA "hologram_system"))
    {:ok, _result} = Connection.query(~s(CREATE SCHEMA "hologram_data"))

    create_system_tables()

    write_marker(%{
      otp_app: context.otp_app,
      env: context.env,
      managed_by: "reconciliation",
      hologram_version: context.hologram_version,
      last_reconciled_at: context.timestamp
    })

    :claimed
  end

  defp deregister(kind, parent, name) do
    statement = """
    DELETE FROM "hologram_system"."schema_object"
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

  defp fill_column(table, column, encoded_value) do
    fill_statement = DDL.fill_statement(table, column)

    {:ok, _result} = Connection.query(fill_statement, [encoded_value])
  end

  defp hologram_schemas do
    statement = """
    SELECT nspname
    FROM pg_catalog.pg_namespace
    WHERE nspname IN ('hologram_data', 'hologram_system')
    ORDER BY nspname
    """

    {:ok, %{rows: rows}} = Connection.query(statement)

    Enum.map(rows, fn [name] -> name end)
  end

  defp log_destructive_op(%{op: :drop_column} = op) do
    Logger.warning(
      ~s(Hologram: schema reconciliation dropped column "#{op.column}" on table "#{op.table}")
    )
  end

  defp log_destructive_op(%{op: :drop_enum_type} = op) do
    Logger.warning(~s(Hologram: schema reconciliation dropped enum type "#{op.enum_type}"))
  end

  defp log_destructive_op(%{op: :drop_table} = op) do
    Logger.warning(~s(Hologram: schema reconciliation dropped table "#{op.table}"))
  end

  defp log_destructive_op(%{op: :rebuild_enum_type} = op) do
    Logger.warning(~s(Hologram: schema reconciliation rebuilt enum type "#{op.enum_type}"))
  end

  defp log_destructive_op(_op), do: :ok

  defp log_destructive_ops(ops) do
    Enum.each(ops, &log_destructive_op/1)
  end

  defp marker_from_context(context) do
    %{
      otp_app: context.otp_app,
      env: context.env,
      managed_by: "reconciliation",
      hologram_version: context.hologram_version,
      last_reconciled_at: context.timestamp
    }
  end

  defp marker_table_exists? do
    statement = """
    SELECT 1
    FROM pg_catalog.pg_class c
    JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
    WHERE n.nspname = 'hologram_system' AND c.relname = 'database' AND c.relkind = 'r'
    """

    {:ok, %{rows: rows}} = Connection.query(statement)

    rows != []
  end

  defp raise_alien!(description) do
    raise "unknown #{description} in the hologram_data schema - " <>
            "this schema is model-managed - " <>
            "move the object to another schema or remove it"
  end

  defp raise_not_managed! do
    raise "the configured database contains Hologram schemas but no managed-database " <>
            "marker - it is not managed by schema reconciliation - drop the " <>
            ~s("hologram_system" and "hologram_data" schemas or point the config ) <>
            "at another database"
  end

  defp qualified_table(table) do
    ~s("hologram_data".#{Mapper.quote_identifier(table)})
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
    DELETE FROM "hologram_system"."schema_object"
    WHERE "kind" = 'index' AND "name" = $1
    """

    {:ok, _result} = Connection.query(statement, [op.index])

    :ok
  end

  defp record_op(%{op: :drop_table} = op) do
    statement = """
    DELETE FROM "hologram_system"."schema_object"
    WHERE ("kind" = 'table' AND "name" = $1) OR "parent" = $1
    """

    {:ok, _result} = Connection.query(statement, [op.table])

    :ok
  end

  defp record_op(%{op: :rebuild_enum_type}), do: :ok

  defp record_op(%{op: :rename_constraint} = op) do
    statement = """
    UPDATE "hologram_system"."schema_object"
    SET "name" = $1
    WHERE "kind" = 'constraint' AND "parent" = $2 AND "name" = $3
    """

    {:ok, _result} = Connection.query(statement, [op.to, op.table, op.from])

    :ok
  end

  defp record_op(%{op: :rename_enum_value}), do: :ok

  defp register(kind, parent, name) do
    statement = """
    INSERT INTO "hologram_system"."schema_object" ("kind", "parent", "name")
    VALUES ($1, $2, $3)
    ON CONFLICT DO NOTHING
    """

    {:ok, _result} = Connection.query(statement, [Atom.to_string(kind), parent, name])

    :ok
  end
end
