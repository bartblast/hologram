defmodule Hologram.DB do
  @moduledoc false

  use Supervisor

  alias Hologram.Auth.Context
  alias Hologram.DB.Clock
  alias Hologram.DB.Config
  alias Hologram.DB.Connection
  alias Hologram.DB.EntityOperations
  alias Hologram.DB.Mapper
  alias Hologram.DB.QueryRunner
  alias Hologram.DB.SchemaReconciler
  alias Hologram.DB.Writer
  alias Hologram.Entity.Validator
  alias Hologram.Migrator
  alias Hologram.Query
  alias Hologram.Reflection
  alias Hologram.WriteError

  @mapping_key {__MODULE__, :mapping}

  @pool_name Hologram.DB.Pool

  @doc """
  Inserts the given entity as a full row - every column is named and bound explicitly -
  stamping created_at and updated_at with the same current UTC timestamp.

  Returns {:ok, entity} with the stamped entity, or {:error, violations} - the map
  Entity.validate/1 returns, naming each field that broke its declaration: the declared
  constraints its value breaks (type, enum values, required presence, the constraint
  options), :unique for a unique attribute whose value another row already holds, and
  :not_found for a to-one reference whose target row does not exist. Values are judged
  before any SQL runs, and a write is attempted only once they pass. Uniqueness and
  reference existence are reported by the write itself for the constraint it refuses, and
  asked advisorily for every unique attribute and to-one reference the write did not answer
  for - an advisory answer describes the moment it was asked, and a value free then can be
  taken by the next attempt. A write refuses at the first violated database constraint and
  reports no other of its own.

  With an acting user set, the write is evaluated against that user's policies for :create - or
  for the operation the entity claims through authorize/2 - against the row being inserted, and
  raises Hologram.AccessDeniedError when no rule grants it. An entity claiming the server's own
  authority through trust/1 is written without evaluation. Without an acting user an unclaimed
  write is raw - the trusted tier - and a claimed operation is evaluated with the anonymous
  semantics. The returned entity carries no claim and no recorded changes.

  Misuse raises rather than returning - a role grant, which is written only through
  grant_role/revoke_role - as does a constraint violation the mapping does not explain.
  """
  @spec create(struct) :: {:ok, struct} | {:error, %{atom => list(atom | {atom, any})}}
  def create(entity) do
    Validator.validate_writable!(entity.__struct__)

    Writer.create(entity)
  end

  @doc """
  Like create/1, returning the stamped entity directly and raising Hologram.WriteError
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
        entity_type = entity.__struct__

        raise WriteError,
          message:
            "cannot create #{inspect(entity_type)}:\n" <>
              refusal_lines(entity_type, violations, Map.from_struct(entity)),
          reason: violations
    end
  end

  @doc """
  Deletes the entity of the given type with the given id together with its own outgoing
  to-many edges, in one transaction. An incoming reference from another entity - a
  to-one reference column or an edge pointing at this entity - restricts the delete,
  returning {:error, %{referenced_by: entity_type, relationship: name}} naming the entity
  type and relationship that still reference the row, with nothing deleted. PostgreSQL
  reports the first such reference only. This is the one translated constraint error - any
  other constraint violation raises. Deleting a nonexistent id is a no-op. Returns :ok.

  With an acting user set, the delete is evaluated against that user's policies for :delete,
  against the row as it stands, read FOR UPDATE - naming the row by type and id carries no
  claim, so delete/1 is the spelling for one on another operation's authority. Without an
  acting user the delete is raw.
  """
  @spec delete(module, String.t()) :: :ok | {:error, %{referenced_by: module, relationship: atom}}
  def delete(entity_type, id) do
    Validator.validate_writable!(entity_type)

    Writer.delete(entity_type, id)
  end

  @doc """
  Deletes the given entity struct together with its own outgoing to-many edges, in one
  transaction, and returns :ok. delete/2 for a struct in hand rather than a type and an id -
  an incoming reference restricts it the same way, returning
  {:error, %{referenced_by: entity_type, relationship: name}}, and a struct whose id names no
  row is a no-op.

  With an acting user set, the delete is evaluated against that user's policies for :delete -
  or for the operation the entity claims through authorize/2 - against the row as it stands,
  read FOR UPDATE, and raises Hologram.AccessDeniedError when no rule grants it. An entity
  claiming the server's own authority through trust/1 is deleted without evaluation, and
  without an acting user an unclaimed delete is raw. A struct whose id names no row is not
  evaluated at all: there is nothing to authorize against.
  """
  @spec delete(struct) :: :ok | {:error, %{referenced_by: module, relationship: atom}}
  def delete(entity) when is_struct(entity) do
    Validator.validate_writable!(entity.__struct__)

    Writer.delete(entity)
  end

  @doc """
  Like delete/1, raising Hologram.WriteError instead of returning {:error, ...}.

  The spelling for seeds, scripts and fixtures, as create!/1 is - code that acts on a
  restriction takes delete/1. A denied claim raises Hologram.AccessDeniedError from either.
  """
  @spec delete!(struct) :: :ok
  def delete!(entity) when is_struct(entity) do
    case delete(entity) do
      :ok ->
        :ok

      {:error, %{referenced_by: referenced_by, relationship: relationship} = reason} ->
        raise WriteError,
          message:
            "cannot delete #{inspect(entity.__struct__)} #{inspect(entity.id)} - still " <>
              "referenced by #{inspect(referenced_by)} through #{inspect(relationship)}",
          reason: reason
    end
  end

  @doc """
  Like delete/2, raising Hologram.WriteError instead of returning {:error, ...}.

  The spelling for seeds, scripts and fixtures, as create!/1 is - code that acts on a conflict
  takes delete/2.
  """
  @spec delete!(module, String.t()) :: :ok
  def delete!(entity_type, id) do
    case delete(entity_type, id) do
      :ok ->
        :ok

      {:error, %{referenced_by: referenced_by, relationship: relationship} = reason} ->
        raise WriteError,
          message:
            "cannot delete #{inspect(entity_type)} #{inspect(id)} - still referenced by " <>
              "#{inspect(referenced_by)} through #{inspect(relationship)}",
          reason: reason
    end
  end

  @doc """
  Executes the given SQL statement with the given placeholders and returns {:ok, result} or
  {:error, exception}. Inside transaction/2 the statement runs on the transaction's
  connection, otherwise on the pool.
  """
  @spec query(String.t(), list, keyword) :: {:ok, Postgrex.Result.t()} | {:error, Exception.t()}
  defdelegate query(statement, placeholders \\ [], opts \\ []), to: Connection

  @doc """
  Reads the given query from the database and returns its result - a list of entity
  structs for set queries, an entity struct or nil for single-result queries, and an
  integer for counting queries.

  The query is an entity type module (the whole entity set) or a query term built with
  Hologram.Query stages. Directly executed query terms embed concrete runtime values -
  the query registry is never involved. A term containing placeholder leaves raises
  ArgumentError: placeholders exist only in compiler-registered queries.

  A :string ordering reads the attribute's sort-key companion column, which every
  :string attribute derives.

  With an acting user set, the query is read through that user's :read policies - the rows the
  policies grant, each included relationship filtered by its own type's :read rules, a
  single-result query answering nil and a counting query counting only what the user may read -
  exactly as a template's registered query is. Without an acting user the query is read raw:
  the trusted tier, for seeds, tasks and jobs.

  A query marked with trust/1 is read raw whether or not a user is acting - the server's own
  authority, the spelling for a read that must see past the acting user's policies.
  """
  @spec read(module | %{atom => any}) :: list(struct) | struct | integer | nil
  def read(query) do
    term = Query.normalize(query)

    assert_no_placeholders!(term)

    actor_user_id = Context.actor_user_id()

    if term[:trust] == true or is_nil(actor_user_id) do
      QueryRunner.run(term, mapping())
    else
      QueryRunner.run_policied(term, mapping(), actor_user_id)
    end
  end

  @doc """
  Returns the entity of the given type with the given id, or nil when no row matches -
  read/1 with one more predicate and single-result cardinality. Column values are decoded
  back into their logical types.

  With an acting user set, the row is read through that user's :read policies and a row the
  policies withhold reads as nil - as if it did not exist, which is what the template tier and
  the client answer. Without an acting user the row is read raw.

  Raises ArgumentError when the id is not a canonical entity id (a lowercase
  8-4-4-4-12 UUID string), or when the first argument is not an entity type module.
  """
  @spec read(module, String.t()) :: struct | nil
  def read(entity_type, id) do
    EntityOperations.validate_id!(id)
    validate_entity_type!(entity_type)

    entity_type
    |> Query.filter(id: id)
    |> Query.one()
    |> read()
  end

  @doc """
  Aborts the innermost enclosing transaction/2, making it return {:error, reason}. Raises
  ArgumentError when called outside of a transaction.
  """
  @spec rollback(any) :: no_return
  defdelegate rollback(reason), to: Connection

  @doc """
  Runs the given zero-arity function inside a database transaction and returns
  {:ok, result}, or {:error, reason} when the function calls rollback/1.

  A nested call opens a savepoint: its own rollback/1 or exception undoes what it wrote
  and nothing more, and the enclosing transaction continues. The write verbs answer the
  same way inside a transaction as outside it - a refused write returns {:error,
  violations} or raises through its bang, and the transaction stays usable. An exception
  rolls the transaction back and re-raises.

  A nested call costs two statements (SAVEPOINT and RELEASE, three when it rolls back),
  and PostgreSQL caches 64 subtransactions per session - a transaction opening more than that, such as a loop of
  writes inside one transaction/2, slows every other session's visibility checks for as
  long as it runs. Split such batches into transactions of their own.
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

  Returns :ok, or {:error, violations} - the map Entity.validate/2 returns, naming each
  changed field that broke its declaration: the declared constraints its value breaks (type,
  enum values, the required-nil rule, the constraint options), :unique for a changed unique
  attribute whose new value another row already holds, and :not_found for a changed to-one
  reference whose target row does not exist. A row's own current value never conflicts with
  itself. Values are judged before any SQL runs, and a write is attempted only once they pass.
  Uniqueness and reference existence are reported by the write itself for the constraint it
  refuses, and asked advisorily for every changed unique attribute and changed to-one reference
  the write did not answer for - an advisory answer describes the moment it was asked, and a
  value free then can be taken by the next attempt. A write refuses at the first violated
  database constraint and reports no other of its own.

  The misuses named above raise rather than returning, as does a constraint violation the
  mapping does not explain.

  With an acting user set, the update is evaluated against that user's policies for :update,
  against the row as it stands, read FOR UPDATE - naming the row by type and id carries no
  claim, so update/1 is the spelling for one on another operation's authority. Without an
  acting user the update is raw.
  """
  @spec update(module, String.t(), map | keyword) ::
          :ok | {:error, %{atom => list(atom | {atom, any})}}
  def update(entity_type, id, changes) do
    Validator.validate_writable!(entity_type)

    Writer.update(entity_type, id, changes)
  end

  @doc """
  Writes the changes recorded on the given entity struct - the values put on it with
  put_attribute, the amounts recorded with increment and decrement, and the edges recorded with
  add_relationship and delete_relationship - in one transaction, and returns :ok.

  Only recorded changes are written: a field set directly on the struct is not among them, and
  a struct carrying nothing recorded raises ArgumentError, as does an id that names no entity.
  The attribute changes go first and the edges follow, so a refused value leaves the edges
  unapplied and an edge that raises takes the values with it.

  With an acting user set, the write is evaluated against that user's policies for :update - or
  for the operation the entity claims through authorize/2 - and raises
  Hologram.AccessDeniedError when no rule grants it. The row is read FOR UPDATE first and the
  claim is evaluated against it as it stands, before the recorded changes apply, so a rule
  describing the state a change leaves ("an editor may pin a note that is not pinned") reads
  the way it reads in a template. Nothing can change the row between the evaluation and the
  write. An entity claiming the server's own authority through trust/1 is written without
  evaluation, and without an acting user an unclaimed write is raw.

  Returns {:error, violations} for a refused value exactly as update/3 does. A moved attribute is
  judged on the value the write leaves, so a move that would cross a declared bound is reported
  the same way.
  """
  @spec update(struct) :: :ok | {:error, %{atom => list(atom | {atom, any})}}
  def update(entity) when is_struct(entity) do
    Validator.validate_writable!(entity.__struct__)

    Writer.update(entity)
  end

  @doc """
  Like update/1, raising Hologram.WriteError instead of returning {:error, ...}.

  The spelling for seeds, scripts and fixtures, as create!/1 is - code that acts on a conflict
  takes update/1. A denied claim raises Hologram.AccessDeniedError from either.
  """
  @spec update!(struct) :: :ok
  def update!(entity) when is_struct(entity) do
    case update(entity) do
      :ok ->
        :ok

      {:error, violations} ->
        entity_type = entity.__struct__

        raise WriteError,
          message:
            "cannot update #{inspect(entity_type)} #{inspect(entity.id)}:\n" <>
              refusal_lines(entity_type, violations, entity.__meta__.attribute_changes),
          reason: violations
    end
  end

  @doc """
  Like update/3, raising Hologram.WriteError instead of returning {:error, ...}.

  The spelling for seeds, scripts and fixtures, as create!/1 is - code that acts on a conflict
  takes update/3.
  """
  @spec update!(module, String.t(), map | keyword) :: :ok
  def update!(entity_type, id, changes) do
    case update(entity_type, id, changes) do
      :ok ->
        :ok

      {:error, violations} ->
        raise WriteError,
          message:
            "cannot update #{inspect(entity_type)} #{inspect(id)}:\n" <>
              refusal_lines(entity_type, violations, Map.new(changes)),
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

    # The clock every server-tier write stamps its column revisions from - a boot-time fact like
    # the mapping, and read the same way.
    Clock.init()

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

  defp assert_no_placeholders!(term) do
    case Query.placeholder_names(term) do
      [] ->
        :ok

      [name | _rest] ->
        raise ArgumentError,
          message:
            "cannot read a query term containing placeholders - placeholder #{inspect(name)} has no value: directly executed queries embed concrete runtime values, placeholders exist only in compiler-registered queries"
    end
  end

  # One line per violation, always bulleted - the shape Validator.error_message/3 set, and the
  # only one that reads the same whether the map holds one entry or several. A taken value is
  # described here because the validator never reports uniqueness: it is state, not a value.
  # A missing reference target is described here for the same reason - existence is state too.
  defp refusal_lines(entity_type, violations, values) do
    violations
    |> Enum.flat_map(fn {field, reasons} -> Enum.map(reasons, &{field, &1}) end)
    |> Enum.sort()
    |> Enum.map_join("\n", fn
      {field, :unique} ->
        "  * attribute #{inspect(field)} #{inspect(Map.fetch!(values, field))} is already taken"

      {field, :not_found} ->
        "  * reference #{inspect(field)} #{inspect(Map.fetch!(values, field))} names no existing entity"

      violation ->
        Validator.violation_description(entity_type, values, violation)
    end)
  end

  # A by-id read is indexed by the entity type, the way delete/2 and update/3 are - a query
  # term reaches the same row through read/1, which is where the stages compose.
  defp validate_entity_type!(query) do
    if not Reflection.entity?(query) do
      raise ArgumentError,
        message:
          "#{inspect(query)} is not an entity type module - a by-id read takes the entity type, a query term is read with read/1"
    end

    :ok
  end
end
