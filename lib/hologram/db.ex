defmodule Hologram.DB do
  @moduledoc false

  use Supervisor

  require Hologram.Query

  alias Hologram.Auth.Context
  alias Hologram.DB.Clock
  alias Hologram.DB.Config
  alias Hologram.DB.Connection
  alias Hologram.DB.EntityOperations
  alias Hologram.DB.Mapper
  alias Hologram.DB.QueryRunner
  alias Hologram.DB.SchemaReconciler
  alias Hologram.DB.SQLQuery
  alias Hologram.DB.Writer
  alias Hologram.Entity
  alias Hologram.Entity.Model
  alias Hologram.Entity.Validator
  alias Hologram.Migrator
  alias Hologram.Query
  alias Hologram.Query.Stage
  alias Hologram.Reflection
  alias Hologram.SQLError
  alias Hologram.WriteError

  @mapping_key {__MODULE__, :mapping}

  @pool_name Hologram.DB.Pool

  @typedoc """
  What an SQL read answers: the column names as strings, in the order the select list named them,
  and the rows as lists of values in that same order.
  """
  @type sql_result :: %{columns: [String.t()], rows: [list]}

  # The data surface, brought in by one line: the stages that build a query term or record a write
  # on an entity struct as bare functions and macros, and the modules the executors live on as
  # aliases. Named after the database rather than after the query, because a module says this
  # line to read or write data - a page that queries, a command that writes, a seed that only
  # creates, a job that only enqueues - and the write stages are the database's vocabulary as much
  # as the query's.
  defmacro __using__(_opts) do
    quote do
      import Hologram.Query,
        only: [
          add_relationship: 3,
          authorize: 2,
          count: 1,
          decrement: 3,
          delete_relationship: 3,
          filter: 2,
          include: 2,
          include: 3,
          increment: 3,
          one: 1,
          paginate: 2,
          put_attribute: 2,
          put_attribute: 3,
          skip: 2,
          sort: 2,
          take: 2,
          trust: 1
        ]

      alias Hologram.DB
      alias Hologram.Entity
      alias Hologram.Job
    end
  end

  @doc """
  Inserts the given entity as a full row - every column is named and bound explicitly -
  stamping created_at and updated_at with the same current UTC timestamp.

  Returns {:ok, entity} with the stamped entity, or {:error, violations} - the map
  Entity.validate/1 returns, naming each field that broke its declaration: the declared
  constraints its value breaks (type, enum values, required presence, the constraint
  options), :unique for a unique attribute whose value another row already holds or a unique
  to-one reference whose target another row already references, and :not_found for a to-one
  reference whose target row does not exist. Values are judged before any SQL runs, and a
  write is attempted only once they pass. Uniqueness and reference existence are reported by
  the write itself for the constraint it refuses, and asked advisorily for every unique
  attribute and to-one reference the write did not answer for - an advisory answer describes
  the moment it was asked, and a value free then can be taken by the next attempt. A write
  refuses at the first violated database constraint and reports no other of its own.

  With an acting user set, the write is evaluated against that user's policies for :create - or
  for the operation the entity claims through authorize/2 - against the row being inserted, and
  raises Hologram.AccessDeniedError when no rule grants it. The grant rows the answer rests on
  are held until the write commits, so a revocation of one of them lands after the write, and a
  grant made meanwhile is not seen - the write is refused where a moment later it would pass.
  Every related row a rule reads - a `via:` target, or a row along a path - is held the same way,
  so a change to it lands after the write. An entity claiming the server's own authority through
  trust/1 is written without evaluation. Without an acting user an unclaimed write is raw - the
  trusted tier - and a claimed operation is evaluated with the anonymous semantics. The returned
  entity carries no claim and no recorded changes.

  A write PostgreSQL aborts as a deadlock victim - its holds crossing another transaction's
  locks - is run again and answers the way it would have a moment later, a refusal included.
  Inside a caller's transaction the deadlock error propagates instead, and the caller's
  transaction is the one to retry.

  Misuse raises rather than returning - a role grant, which is written only through
  grant_role/revoke_role, and a job, which is created through Job.create/2 - as does a
  constraint violation the mapping does not explain.
  """
  @spec create(Entity.t()) :: {:ok, Entity.t()} | {:error, %{atom => list(atom | {atom, any})}}
  def create(entity) do
    validate_not_job!(entity.__struct__)
    Validator.validate_writable!(entity.__struct__)

    Writer.create(entity)
  end

  @doc """
  Like create/1, returning the stamped entity directly and raising Hologram.WriteError
  instead of returning {:error, ...}.

  The spelling for seeds, scripts and fixtures, where a conflict is a reason to stop rather than
  something to answer. Code that acts on a conflict - a command handling a form - takes create/1.
  """
  @spec create!(Entity.t()) :: Entity.t()
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
  claim, so delete/1 is the spelling for one on another operation's authority. The grant rows
  the answer rests on are held until the delete commits, so a revocation of one of them lands
  after the delete, and a grant made meanwhile is not seen - the delete is refused where a moment
  later it would pass. Every related row a rule reads - a `via:` target, or a row along a path -
  is held the same way, so a change to it lands after the delete. Without an acting user the
  delete is raw.

  A delete PostgreSQL aborts as a deadlock victim - its holds crossing another transaction's
  locks - is run again and answers the way it would have a moment later, a refusal included.
  Inside a caller's transaction the deadlock error propagates instead, and the caller's
  transaction is the one to retry.
  """
  @spec delete(module, Entity.id()) ::
          :ok | {:error, %{referenced_by: module, relationship: atom}}
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
  read FOR UPDATE, and raises Hologram.AccessDeniedError when no rule grants it. The grant rows
  the answer rests on are held until the delete commits, so a revocation of one of them lands
  after the delete, and a grant made meanwhile is not seen - the delete is refused where a moment
  later it would pass. Every related row a rule reads - a `via:` target, or a row along a path -
  is held the same way, so a change to it lands after the delete. An entity claiming the server's
  own authority through trust/1 is deleted without evaluation, and without an acting user an
  unclaimed delete is raw. A struct whose id names no row is not evaluated at all: there is
  nothing to authorize against.

  A delete PostgreSQL aborts as a deadlock victim - its holds crossing another transaction's
  locks - is run again and answers the way it would have a moment later, a refusal included.
  Inside a caller's transaction the deadlock error propagates instead, and the caller's
  transaction is the one to retry.
  """
  @spec delete(Entity.t()) :: :ok | {:error, %{referenced_by: module, relationship: atom}}
  def delete(entity) when is_struct(entity) do
    Validator.validate_writable!(entity.__struct__)

    Writer.delete(entity)
  end

  @doc """
  Like delete/1, raising Hologram.WriteError instead of returning {:error, ...}.

  The spelling for seeds, scripts and fixtures, as create!/1 is - code that acts on a
  restriction takes delete/1. A denied claim raises Hologram.AccessDeniedError from either.
  """
  @spec delete!(Entity.t()) :: :ok
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
  @spec delete!(module, Entity.id()) :: :ok
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
  Returns the name of the join table behind the given to-many relationship of the given entity
  type, unquoted, for SQL written by hand.

  The name is `<source table>_<relationship>_$join`, cut to a prefix and a hash past PostgreSQL's
  63-byte limit, and the table has the columns `source_id` and `target_id`. The `$` means it has to
  be quoted in SQL. The name follows the model: renaming the entity type or the relationship moves
  it, so code that asks for it keeps working where a name written out would break.

  Raises ArgumentError when the first argument is not an entity type module, or when the
  relationship is a to-one relationship or not declared.
  """
  @spec join_table_name(module, atom) :: String.t()
  def join_table_name(entity_type, relationship) do
    validate_entity_type!(
      entity_type,
      "join_table_name/2 takes an entity type and the name of one of its to-many relationships"
    )

    join_table =
      entity_type
      |> Mapper.join_tables()
      |> Enum.find(&(&1.relationship == relationship))

    case join_table do
      %{name: name} -> name
      nil -> raise ArgumentError, message: join_table_refusal(entity_type, relationship)
    end
  end

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
  @spec read(module | Query.t()) :: list(Entity.t()) | Entity.t() | integer | nil
  def read(query) do
    term = Stage.normalize(query)

    assert_no_placeholders!(term)

    actor_user_id = Context.actor_user_id()

    if term.trust or is_nil(actor_user_id) do
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
  @spec read(module, Entity.id()) :: Entity.t() | nil
  def read(entity_type, id) do
    EntityOperations.validate_id!(id)

    validate_entity_type!(
      entity_type,
      "a by-id read takes the entity type, a query term is read with read/1"
    )

    entity_type
    |> Query.filter(id: ^id)
    |> Query.one()
    |> read()
  end

  @doc """
  Aborts the innermost enclosing transaction, making it return {:error, reason}. Raises
  ArgumentError when called outside of a transaction.
  """
  @spec rollback(any) :: no_return
  defdelegate rollback(reason), to: Connection

  @doc """
  Returns the name of the PostgreSQL schema every entity table and join table lives in, unquoted,
  for SQL written by hand.
  """
  @spec schema_name() :: String.t()
  def schema_name, do: Mapper.data_schema()

  @doc """
  Runs one SQL statement on the server against the data layer's tables and returns
  {:ok, result} or {:error, error}. The statement is prepared, with its `$1`-style placeholders
  bound from params - a param is never spliced into the text - and the result is a map:
  :columns, the names as strings in the order the select list named them, and :rows, one list of
  values per row in that same order. Two columns of one name both stay, at their positions.

  This is the read the query stages cannot say: full-text search, aggregates and grouping, window
  functions, CTEs, a report joining several entity types, a search over data that is not synced.
  The names of the schema, of an entity type's table and of a to-many relationship's join table
  come from this module at run time, quoted in the SQL - a join table's name carries `$`, and an
  attribute may be named by a reserved word (`"user"` unquoted is the database role). An
  attribute's column has the attribute's name, a to-one relationship's column is `<name>_id`,
  every table has `id`, `created_at` and `updated_at`, and a join table has `source_id` and
  `target_id`. Columns whose names contain `$` are the framework's own, and what they hold can
  change between versions. Select attributes by name.

  Policies do not apply: the read sees every row. A read on behalf of a user keeps to what that
  user may see in the SQL itself.

  The statement runs in a read-only transaction, so a write of any kind - an insert, update,
  delete or truncate, DDL, a row lock, `nextval()`, a writing CTE, a function that writes - is
  refused by PostgreSQL and answered as {:error, %Hologram.SQLError{code:
  :read_only_sql_transaction}} with a message saying so. A write that skipped the data layer would
  never reach the sync, and clients would drift from the server with nothing failing. Any other
  failure - a syntax error, a missing table, a type mismatch in the SQL, a timeout - is
  {:error, %Hologram.SQLError{}} carrying the server's condition name as its code and the server's
  message.

  A uuid column or uuid array comes back as canonical id strings, the spelling every entity
  carries, and an id string given for a uuid parameter or uuid array parameter is encoded for the
  driver - a 16-byte binary passes through either way. The conversion goes by the types PostgreSQL
  reports for the statement, so a text column holding a uuid-shaped string stays as it is. Other
  types arrive as the driver decodes them: `int8` as an integer, `float8` as a float, `text` as a
  string, `boolean`, `date` as a Date, `time` as a Time, `timestamptz` as a DateTime, an enum as
  its label string and `jsonb` as a map.

  Inside an enclosing transaction the statement runs on the transaction's connection and sees its
  uncommitted rows, and the transaction stays writable afterwards.

  Runs only on the server: a page whose client code reaches it fails the build. Call it from a
  command, a job, a seed or a script, and hand an action what the client needs. A row is not an
  entity, so nothing strips server-only attribute values from it - a selected `password_hash` put
  in state reaches the client. Select what the client may see.

  The one option is `timeout:`, the milliseconds the statement may run as a positive integer up
  to 2_147_483_647, the largest PostgreSQL accepts, or `:infinity` - fifteen seconds by default.
  PostgreSQL enforces it: past it the statement is cancelled and answered as
  {:error, %Hologram.SQLError{code: :query_canceled}}, and the connection and any enclosing
  transaction carry on. Inside an enclosing transaction its own bound applies as well. The read
  is not run again when PostgreSQL resolves a deadlock, since it takes no row locks.

  Raises ArgumentError for a statement that takes a session-level advisory lock or prepares a
  named statement, either of which would outlive the read on a pooled connection - a
  transaction-level advisory lock taken inside an enclosing transaction is held until that
  transaction ends. Raises it as well for an option other than `timeout:`, an invalid timeout, a
  number of params that differs from the statement's placeholders, and a param that does not fit
  its placeholder's type. None of these reaches the server.
  """
  @spec sql(String.t(), list, keyword) :: {:ok, sql_result} | {:error, SQLError.t()}
  def sql(statement, params \\ [], opts \\ []) do
    SQLQuery.run(statement, params, opts)
  end

  @doc """
  Runs one SQL statement on the server, read-only, the same way the non-raising variant does,
  returning the result map directly and raising the Hologram.SQLError where that variant returns
  {:error, error}.
  """
  @spec sql!(String.t(), list, keyword) :: sql_result
  def sql!(statement, params \\ [], opts \\ []) do
    case sql(statement, params, opts) do
      {:ok, result} -> result
      {:error, error} -> raise error
    end
  end

  @doc """
  Returns the name of the given entity type's table, unquoted, for SQL written by hand.

  The name is the module path snake-cased with the app's root namespace stripped
  (`MyApp.Chat.Message` is `chat_message`), a module from another root keeps its whole path,
  framework types are pinned (`hologram_role_grant`), and a name past PostgreSQL's 63-byte limit is
  cut to a prefix and a hash. The name follows the model: renaming the entity type moves it, so
  code that asks for it keeps working where a name written out would break.

  Raises ArgumentError when the argument is not an entity type module.
  """
  @spec table_name(module) :: String.t()
  def table_name(entity_type) do
    validate_entity_type!(entity_type, "table_name/1 takes an entity type")

    Mapper.table_name(entity_type)
  end

  @doc """
  Runs the given zero-arity function inside a database transaction and returns
  {:ok, result}, or {:error, reason} when the function aborts the transaction with a reason.

  A nested call opens a savepoint: its own abort or exception undoes what it wrote and nothing
  more, and the enclosing transaction continues. The write verbs answer the
  same way inside a transaction as outside it - a refused write returns {:error,
  violations} or raises through its bang, and the transaction stays usable. An exception
  rolls the transaction back and re-raises. A write verb called inside it is not run again when
  PostgreSQL aborts the transaction as a deadlock victim - the error propagates, and this
  transaction is the one to retry.

  A nested call costs two statements (SAVEPOINT and RELEASE, three when it rolls back), and
  PostgreSQL caches 64 subtransactions per session - a transaction opening more than that, such
  as a loop of writes inside one transaction, slows every other session's visibility checks for
  as long as it runs. Split such batches into transactions of their own.
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
  attribute whose new value another row already holds or a changed unique to-one reference
  whose new target another row already references, and :not_found for a changed to-one
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
  claim, so update/1 is the spelling for one on another operation's authority. The grant rows
  the answer rests on are held until the update commits, so a revocation of one of them lands
  after the update, and a grant made meanwhile is not seen - the update is refused where a moment
  later it would pass. Every related row a rule reads - a `via:` target, or a row along a path -
  is held the same way, so a change to it lands after the update. Without an acting user the
  update is raw.

  An update PostgreSQL aborts as a deadlock victim - its holds crossing another transaction's
  locks - is run again and answers the way it would have a moment later, a refusal included.
  Inside a caller's transaction the deadlock error propagates instead, and the caller's
  transaction is the one to retry.
  """
  @spec update(module, Entity.id(), map | keyword) ::
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
  write, and the grant rows the answer rests on are held until the write commits, so a
  revocation of one of them lands after the write, and a grant made meanwhile is not seen - the
  write is refused where a moment later it would pass. Every related row a rule reads - a `via:`
  target, or a row along a path - is held the same way, so a change to it lands after the write.
  An entity claiming the server's own authority through trust/1 is written without evaluation, and
  without an acting user an unclaimed write is raw.

  An update PostgreSQL aborts as a deadlock victim - its holds crossing another transaction's
  locks - is run again and answers the way it would have a moment later, a refusal included.
  Inside a caller's transaction the deadlock error propagates instead, and the caller's
  transaction is the one to retry.

  Returns {:error, violations} for a refused value exactly as update/3 does. A moved attribute is
  judged on the value the write leaves, so a move that would cross a declared bound is reported
  the same way.
  """
  @spec update(Entity.t()) :: :ok | {:error, %{atom => list(atom | {atom, any})}}
  def update(entity) when is_struct(entity) do
    Validator.validate_writable!(entity.__struct__)

    Writer.update(entity)
  end

  @doc """
  Like update/1, raising Hologram.WriteError instead of returning {:error, ...}.

  The spelling for seeds, scripts and fixtures, as create!/1 is - code that acts on a conflict
  takes update/1. A denied claim raises Hologram.AccessDeniedError from either.
  """
  @spec update!(Entity.t()) :: :ok
  def update!(entity) when is_struct(entity) do
    case update(entity) do
      :ok ->
        :ok

      {:error, violations} ->
        entity_type = entity.__struct__

        raise WriteError,
          message:
            "cannot update #{inspect(entity_type)} #{inspect(entity.id)}:\n" <>
              refusal_lines(entity_type, violations, put_values(entity.__meta__.attribute_ops)),
          reason: violations
    end
  end

  @doc """
  Like update/3, raising Hologram.WriteError instead of returning {:error, ...}.

  The spelling for seeds, scripts and fixtures, as create!/1 is - code that acts on a conflict
  takes update/3.
  """
  @spec update!(module, Entity.id(), map | keyword) :: :ok
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
  Derives and caches the mapping and creates the node's clock: what the database sets up
  before it has a server, and what code reading the mapping or stamping a write needs
  whether or not one is running. Returns :ok.
  """
  @spec put_boot_facts() :: :ok
  def put_boot_facts do
    # The mapping derived here is the one every consumer reads for the lifetime of the
    # runtime - companions included, since they derive from the declarations like every
    # other column.
    mapping = Mapper.derive!(Model.entity_types(), Model.roles())
    :persistent_term.put(@mapping_key, mapping)

    # The clock every server-tier write stamps its column revisions from - a boot-time fact like
    # the mapping, and read the same way.
    Clock.init()
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

  @doc false
  @spec refusal_lines(module, %{atom => list(atom | {atom, any})}, %{atom => any}) :: String.t()
  def refusal_lines(entity_type, violations, values) do
    violations
    |> Enum.flat_map(fn {field, reasons} -> Enum.map(reasons, &{field, &1}) end)
    |> Enum.sort()
    |> Enum.map_join("\n", fn
      {field, :unique} ->
        "  * #{unique_kind(entity_type, field)} #{inspect(field)} #{inspect(Map.fetch!(values, field))} is already taken"

      {field, :not_found} ->
        "  * reference #{inspect(field)} #{inspect(Map.fetch!(values, field))} names no existing entity"

      violation ->
        Validator.violation_description(entity_type, values, violation)
    end)
  end

  # A by-id read is indexed by the entity type, the way delete/2 and update/3 are - a query
  # term reaches the same row through read/1, which is where the stages compose.

  @doc """
  Re-derives and re-caches the mapping from the given entity type and global role modules,
  then reconciles the schema. A no-op when the database is not running (no entities declared
  at boot). Returns :ok.
  """
  @spec reload(list(module), list(module)) :: :ok
  def reload(entity_types, role_modules) do
    if Process.whereis(__MODULE__) do
      mapping = Mapper.derive!(entity_types, role_modules)
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
    put_boot_facts()

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
    case Stage.placeholder_names(term) do
      [] ->
        :ok

      [name | _rest] ->
        raise ArgumentError,
          message:
            "cannot read a query term containing placeholders - placeholder #{inspect(name)} has no value: directly executed queries embed concrete runtime values, placeholders exist only in compiler-registered queries"
    end
  end

  # A to-one relationship or an inverse is a name a caller can reasonably expect a join table for and
  # not get, so it is told where that relationship's fact lives instead.
  defp join_table_refusal(entity_type, relationship) do
    declared? =
      Enum.any?(entity_type.__relationships__(), fn {name, _target, _opts} ->
        name == relationship
      end)

    inverse = Entity.inverse_relationship(entity_type, relationship)

    cond do
      inverse && inverse.reference? ->
        "relationship #{inspect(relationship)} of #{inspect(entity_type)} is an inverse - it " <>
          "reads the #{inverse.forward}_id column of #{inspect(inverse.target)}'s table, and a " <>
          "join table backs a stored to-many relationship only"

      inverse ->
        "relationship #{inspect(relationship)} of #{inspect(entity_type)} is an inverse - it " <>
          "reads the join table of #{Entity.describe_inverse(entity_type, relationship)}"

      declared? ->
        "relationship #{inspect(relationship)} of #{inspect(entity_type)} is a to-one " <>
          "relationship, stored as the #{relationship}_id column of the entity's own table - a " <>
          "join table backs a to-many relationship only"

      true ->
        "#{inspect(entity_type)} declares no relationship #{inspect(relationship)}"
    end
  end

  # One line per violation, always bulleted - the shape Validator.error_message/3 set, and the
  # only one that reads the same whether the map holds one entry or several. A taken value is
  # described here because the validator never reports uniqueness: it is state, not a value.
  # A missing reference target is described here for the same reason - existence is state too.
  # The values the struct was asked to write - an increment has none, and its line names no
  # received value.
  defp put_values(attribute_ops) do
    for {name, {:put, value}} <- attribute_ops, into: %{}, do: {name, value}
  end

  # A unique field is a declared attribute or the reference field of a unique to-one, and the line
  # names which, the way the :not_found line names a reference.
  defp unique_kind(entity_type, field) do
    attribute? =
      Enum.any?(entity_type.__attributes__(), fn {name, _type, _opts} -> name == field end)

    if attribute?, do: "attribute", else: "reference"
  end

  defp validate_entity_type!(term, hint) do
    if not Reflection.entity?(term) do
      raise ArgumentError, message: "#{inspect(term)} is not an entity type module - #{hint}"
    end

    :ok
  end

  # A job's create means more than storing a row - it schedules work to run after the transaction
  # commits - so it has one spelling, the way a role grant has one. The message gives the reason
  # rather than the redirect, since the two verbs are now the same word in different modules.
  defp validate_not_job!(entity_type) do
    if Reflection.job?(entity_type) do
      raise ArgumentError,
        message:
          "#{inspect(entity_type)} is a job type - create it through Job.create/2, which records who enqueued it so the worker can run it as them after the transaction commits"
    end

    :ok
  end
end
