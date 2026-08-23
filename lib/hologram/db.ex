defmodule Hologram.DB do
  @moduledoc false

  use Supervisor

  alias Hologram.DB.Config
  alias Hologram.DB.Connection
  alias Hologram.DB.EntityOperations
  alias Hologram.DB.Mapper
  alias Hologram.DB.QueryRunner
  alias Hologram.DB.SchemaReconciler
  alias Hologram.Entity.Validator
  alias Hologram.Migrator
  alias Hologram.Query
  alias Hologram.Reflection
  alias Hologram.WriteConflictError

  @mapping_key {__MODULE__, :mapping}

  @pool_name Hologram.DB.Pool

  @doc """
  Adds the (source, target) edge to the given to-many relationship of the entity with
  the given id. Idempotent - adding an existing edge is a no-op. Returns :ok. Naming
  anything but a declared to-many relationship raises ArgumentError, and a missing
  source or target entity raises through the edge's foreign keys.
  """
  @spec add_relationship(module, String.t(), atom, String.t()) :: :ok
  defdelegate add_relationship(entity_type, id, relationship_name, target_id),
    to: EntityOperations

  @doc """
  Inserts the given entity as a full row - every column is named and bound explicitly -
  stamping created_at and updated_at with the same current UTC timestamp.

  Returns {:ok, entity} with the stamped entity, or {:error, violations} when the value of a
  unique attribute is already held by another row - violations is the map Entity.validate/1
  returns, the attribute name to [:unique]. A write reports the first violated database
  constraint only. Any other constraint violation raises.

  Attribute values are validated against the entity type's declarations before any SQL
  runs - type, enum values, required presence, and the declared constraint options -
  raising one ArgumentError that lists every violation.
  """
  @spec create(struct) :: {:ok, struct} | {:error, %{atom => list(atom)}}
  def create(entity) do
    Validator.validate_writable!(entity.__struct__)

    EntityOperations.create(entity)
  end

  @doc """
  Like create/1, returning the stamped entity directly and raising Hologram.WriteConflictError
  instead of returning {:error, ...}.

  The spelling for seeds, scripts and fixtures, where a conflict is a reason to stop rather than
  something to answer. Code that acts on a conflict - a command handling a form - takes create/1.
  """
  @spec create!(struct) :: struct
  def create!(entity) do
    case create(entity) do
      {:ok, stamped_entity} ->
        stamped_entity

      {:error, violations} ->
        raise WriteConflictError,
          message:
            "cannot create #{inspect(entity.__struct__)} - #{taken_description(violations, entity)}",
          reason: violations
    end
  end

  @doc """
  Deletes the entity of the given type with the given id together with its own outgoing
  to-many edges, in one transaction. An incoming reference from another entity - a
  to-one reference column or an edge pointing at this entity - restricts the delete,
  returning {:error, {:restricted, %{entity_type: entity_type, id: id}}} with nothing
  deleted. This is the one translated constraint error - any other constraint violation
  raises. Deleting a nonexistent id is a no-op. Returns :ok.
  """
  @spec delete(module, String.t()) :: :ok | {:error, {:restricted, map}}
  def delete(entity_type, id) do
    Validator.validate_writable!(entity_type)

    EntityOperations.delete(entity_type, id)
  end

  @doc """
  Deletes the (source, target) edge from the given to-many relationship of the entity
  with the given id. Idempotent - deleting an absent edge is a no-op. Returns :ok.
  Naming anything but a declared to-many relationship raises ArgumentError.
  """
  @spec delete_relationship(module, String.t(), atom, String.t()) :: :ok
  defdelegate delete_relationship(entity_type, id, relationship_name, target_id),
    to: EntityOperations

  @doc """
  Returns the entity of the given type with the given id, or nil when no row matches.
  Column values are decoded back into their logical types.

  Raises ArgumentError when the id is not a canonical entity id (a lowercase
  8-4-4-4-12 UUID string).
  """
  @spec get(module, String.t()) :: struct | nil
  defdelegate get(entity_type, id), to: EntityOperations

  @doc """
  Executes the given SQL statement with the given placeholders and returns {:ok, result} or
  {:error, exception}. Inside transaction/2 the statement runs on the transaction's
  connection, otherwise on the pool.
  """
  @spec query(String.t(), list, keyword) :: {:ok, Postgrex.Result.t()} | {:error, Exception.t()}
  defdelegate query(statement, placeholders \\ [], opts \\ []), to: Connection

  @doc """
  Aborts the enclosing transaction/2, making it return {:error, reason}. Raises
  ArgumentError when called outside of a transaction.
  """
  @spec rollback(any) :: no_return
  defdelegate rollback(reason), to: Connection

  @doc """
  Runs the given query against the database and returns its result - a list of entity
  structs for set queries, an entity struct or nil for single-result queries, and an
  integer for counting queries.

  The query is an entity type module (the whole entity set) or a query term built with
  Hologram.Query stages. Directly executed query terms embed concrete runtime values -
  the query registry is never involved. A term containing placeholder leaves raises
  ArgumentError: placeholders exist only in compiler-registered queries.

  A :string ordering reads the attribute's sort-key companion column, which every
  :string attribute derives.
  """
  @spec run(module | %{atom => any}) :: list(struct) | struct | integer | nil
  def run(query) do
    term = Query.normalize(query)

    assert_no_placeholders!(term)

    QueryRunner.run(term, mapping())
  end

  @doc """
  Runs the given zero-arity function inside a database transaction and returns
  {:ok, result}. Transactions are flat: a nested call joins the ongoing transaction
  instead of nesting - there are no savepoints, and rollback/1 aborts the one flat
  transaction wherever it is called. An exception rolls the transaction back and
  re-raises.
  """
  @spec transaction((-> any), keyword) :: {:ok, any} | {:error, any}
  defdelegate transaction(fun, opts \\ []), to: Connection

  @doc """
  Updates the entity of the given type with the given id, setting exactly the changed
  columns plus updated_at - there is no full-row variant. Changes (a map or keyword list)
  are keyed by declared attribute and to-one relationship names - a to-one reference is
  set, reassigned, or cleared (nil) through its relationship name. Changing any other
  name, system attributes included, raises ArgumentError - as do empty changes and an
  id that names no entity.

  Returns :ok, or {:error, violations} when a changed unique attribute's new value is already
  held by another row - violations is the map Entity.validate/2 returns, the attribute name to
  [:unique]. A row's own current value never conflicts with itself. A write reports the first
  violated database constraint only. Any other constraint violation raises.

  Changed attribute values are validated against the entity type's declarations before
  any SQL runs - type, enum values, the required-nil rule, and the declared constraint
  options - raising one ArgumentError that lists every violation.
  """
  @spec update(module, String.t(), map | keyword) :: :ok | {:error, %{atom => list(atom)}}
  def update(entity_type, id, changes) do
    Validator.validate_writable!(entity_type)

    EntityOperations.update(entity_type, id, changes)
  end

  @doc false
  @spec update(struct) :: no_return
  def update(entity) when is_struct(entity) do
    raise ArgumentError,
          "update takes explicit changes, not a modified struct - pass the changed attributes: " <>
            "DB.update(#{inspect(entity.__struct__)}, entity.id, attribute: value). " <>
            "Full-row writes from a struct aren't supported: they would overwrite concurrent " <>
            "changes to fields you didn't touch."
  end

  @doc """
  Like update/3, raising Hologram.WriteConflictError instead of returning {:error, ...}.

  The spelling for seeds, scripts and fixtures, as create!/1 is - code that acts on a conflict
  takes update/3.
  """
  @spec update!(module, String.t(), map | keyword) :: :ok
  def update!(entity_type, id, changes) do
    case update(entity_type, id, changes) do
      :ok ->
        :ok

      {:error, violations} ->
        raise WriteConflictError,
          message:
            "cannot update #{inspect(entity_type)} #{inspect(id)} - #{taken_description(violations, Map.new(changes))}",
          reason: violations
    end
  end

  @doc """
  Returns the physical name mapping derived from the discovered entity type modules.
  The mapping is derived once at boot and cached for the lifetime of the runtime.
  """
  @spec mapping() :: %{module => %{atom => any}}
  def mapping do
    :persistent_term.get(@mapping_key)
  end

  @doc """
  Returns the key of the persistent term holding the mapping.
  """
  @spec mapping_key() :: any
  def mapping_key, do: @mapping_key

  @doc """
  Runs the migration applier as a one-shot supervision child after the pool starts and
  returns :ignore (no process stays running). A failed apply fails the boot loudly.
  """
  @spec migrate_at_boot() :: :ignore
  def migrate_at_boot do
    Migrator.run()

    :ignore
  end

  @doc """
  Returns the name of the connection pool process.
  """
  @spec pool_name() :: atom
  def pool_name do
    @pool_name
  end

  @doc """
  Runs dev schema reconciliation as a one-shot supervision child after the pool starts
  and returns :ignore (no process stays running). A failed reconciliation fails the
  boot loudly.
  """
  @spec reconcile_at_boot() :: :ignore
  def reconcile_at_boot do
    SchemaReconciler.reconcile(reconciliation_context())

    :ignore
  end

  @doc """
  Returns the context for a schema reconciliation run: the cached mapping, the guard
  facts (otp_app and env as strings), and the marker diagnostics (the Hologram version
  and the current UTC timestamp).
  """
  @spec reconciliation_context() :: %{atom => any}
  def reconciliation_context do
    %{
      mapping: mapping(),
      otp_app: Atom.to_string(Reflection.otp_app()),
      env: Atom.to_string(Hologram.env()),
      hologram_version: to_string(Application.spec(:hologram, :vsn)),
      timestamp: DateTime.utc_now(:microsecond)
    }
  end

  @doc """
  Re-derives and re-caches the mapping from the current entity type modules, then
  reconciles the schema - the live-reload path after a dev code change. A no-op when
  the database is not running (no entities declared at boot). Returns :ok.
  """
  @spec reload() :: :ok
  def reload do
    if Process.whereis(__MODULE__) do
      mapping = Mapper.derive!(Reflection.list_entities())
      :persistent_term.put(@mapping_key, mapping)

      SchemaReconciler.reconcile(reconciliation_context())
    end

    :ok
  end

  @doc """
  Starts the database: derives and caches the mapping, then starts the connection pool -
  in dev, schema reconciliation runs as a one-shot boot step right after the pool is up,
  and outside dev and test the migration applier runs there instead.
  The given opts override the resolved connection options. The database is a VM-wide
  singleton - starting while an instance is already running yields :ignore instead of
  failing the caller's supervision tree.
  """
  @spec start_link(keyword) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    case Supervisor.start_link(__MODULE__, opts, name: __MODULE__) do
      {:error, {:already_started, _pid}} -> :ignore
      other -> other
    end
  end

  @impl Supervisor
  def init(opts) do
    # The mapping derived here is the one every consumer reads for the lifetime of the
    # runtime - companions included, since they derive from the declarations like every
    # other column.
    mapping = Mapper.derive!(Reflection.list_entities())
    :persistent_term.put(@mapping_key, mapping)

    resolved_opts =
      :hologram
      |> Application.get_env(:database, [])
      |> Config.resolve!(Hologram.env())

    # The driver boundary - resolved config uses the component-named keys, Postgrex expects
    # its own option names. Given opts win, so that tests can inject overrides (e.g. an
    # ownership pool).
    postgrex_opts =
      Keyword.merge(
        [
          database: resolved_opts[:database],
          hostname: resolved_opts[:host],
          name: @pool_name,
          password: resolved_opts[:password],
          pool_size: resolved_opts[:pool_size],
          port: resolved_opts[:port],
          username: resolved_opts[:user]
        ],
        opts
      )

    pool_child = {Postgrex, postgrex_opts}

    # The environment selects the schema mechanism: dev converges from the model, test
    # manages its schema from the test helpers, and every other env applies the
    # migration history.
    children =
      case Hologram.env() do
        :dev ->
          [pool_child, %{id: :schema_reconciliation, start: {__MODULE__, :reconcile_at_boot, []}}]

        :test ->
          [pool_child]

        _env ->
          [pool_child, %{id: :migrations, start: {__MODULE__, :migrate_at_boot, []}}]
      end

    Supervisor.init(children, strategy: :one_for_one)
  end

  # Written to describe several fields though a write reports one: PostgreSQL aborts at the
  # first violated constraint, so the map always holds a single key today.
  defp taken_description(violations, values) do
    violations
    |> Enum.sort()
    |> Enum.map_join(", ", fn {field, _reasons} ->
      "#{field} #{inspect(Map.fetch!(values, field))} is already taken"
    end)
  end

  defp assert_no_placeholders!(term) do
    case Query.placeholder_names(term) do
      [] ->
        :ok

      [name | _rest] ->
        raise ArgumentError,
          message:
            "cannot run a query term containing placeholders - placeholder #{inspect(name)} has no value: directly executed queries embed concrete runtime values, placeholders exist only in compiler-registered queries"
    end
  end
end
