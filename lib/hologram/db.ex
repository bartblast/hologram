defmodule Hologram.DB do
  @moduledoc false

  use Supervisor

  require Hologram.Query
  require Logger

  alias Hologram.Auth.Context
  alias Hologram.DB.Clock
  alias Hologram.DB.Config
  alias Hologram.DB.Connection
  alias Hologram.DB.EntityOperations
  alias Hologram.DB.IndexPlan
  alias Hologram.DB.Mapper
  alias Hologram.DB.Protocol
  alias Hologram.DB.QueryRunner
  alias Hologram.DB.SchemaReconciler
  alias Hologram.DB.SQLQuery
  alias Hologram.DB.Writer
  alias Hologram.Entity
  alias Hologram.Entity.Model
  alias Hologram.Entity.Validator
  alias Hologram.Migrator
  alias Hologram.MisuseError
  alias Hologram.Query
  alias Hologram.Query.Stage
  alias Hologram.Reflection
  alias Hologram.SQLError
  alias Hologram.Test.DatabaseBootstrap.Connection, as: ProbeConnection
  alias Hologram.WriteError

  @mapping_key {__MODULE__, :mapping}

  # Set while a template or a derived function runs, so what it reads holds its server-only
  # attributes as placeholders, as what the template is handed does.
  @strip_server_only_key {__MODULE__, :strip_server_only}

  # The index plan the last reconciliation this node ran converged the database to.
  @plan_key {__MODULE__, :plan}

  # How long the boot waits between two tries while the database cannot be reached. Each try also
  # waits for the pool to give up on a checkout, about 4 seconds with DBConnection's defaults, then
  # opens a connection of its own, which a host that drops packets holds for Postgrex's connect
  # timeout of 15 seconds.
  @await_retry_interval_ms :timer.seconds(2)

  @pool_name Hologram.DB.Pool

  # What a server starting up or shutting down answers with - one that is away for a moment rather
  # than one the settings are wrong for. Not a connection limit: a role's or a database's limit
  # answers the same way as the server's, and would hold the boot for good.
  @unavailable_error_codes [:admin_shutdown, :cannot_connect_now, :crash_shutdown]

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
          average: 2,
          count: 1,
          decrement: 3,
          delete_relationship: 3,
          filter: 2,
          include: 2,
          increment: 3,
          inverse: 2,
          most_common: 2,
          one: 1,
          paginate: 2,
          put_attribute: 2,
          put_attribute: 3,
          skip: 2,
          sort: 2,
          sum: 2,
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
  stamping created_at, updated_at, server_created_at and server_updated_at with the same
  current UTC timestamp.

  Returns {:ok, entity} with the stamped entity, or {:error, violations} - the map
  Entity.validate/1 returns, naming each field that broke its declaration: the declared
  constraints its value breaks (type, enum values, required presence, the constraint
  options), :unique for a unique attribute whose value another row already holds or a unique
  to-one reference whose target another row already references, {:unique, fields} on every
  field of a key declared with unique whose values another row already holds together (fields
  being the key's, a to-one named by its reference field), and :not_found for a to-one
  reference whose target row does not exist. Values are judged before any SQL runs, and a
  write is attempted only once they pass. Uniqueness and reference existence are reported by
  the write itself for the constraint it refuses, and asked advisorily for every unique
  attribute, key and to-one reference the write did not answer for - an advisory answer describes
  the moment it was asked, and a value free then can be taken by the next attempt. A write
  refuses at the first violated database constraint and reports no other of its own.

  In a session - a Hologram page, command or middleware, or a job run as the user who created it -
  the write is evaluated against the session user's policies for :create, an anonymous session's
  for a signed-out visitor, against the row being inserted, and raises
  Hologram.AccessDeniedError when no rule grants it.
  The grant rows the answer rests on are held until the write commits, so a revocation of one of
  them lands after the write, and a grant made meanwhile is not seen - the write is refused where
  a moment later it would pass. Every related row a rule reads - a `via:` target, or a row along a
  path - is held the same way, so a change to it lands after the write. An entity claiming the
  server's own authority through trust/1 is written without evaluation, and code outside a session,
  like a seed, a Mix task, a console or an app's own plug or controller, writes raw - the trusted
  tier. A session user id no user
  entity can have - an app's own serial id - is evaluated as an anonymous session too, so server
  code in a session that means to write past the rules claims trust/1. The returned entity
  carries no claim and no recorded changes.

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

  In a session, the delete is evaluated against the session user's policies for :delete, an
  anonymous session's for a signed-out visitor, against the row as it stands, read FOR UPDATE -
  naming the row by type and id carries no claim, so a trusted delete is `entity |> trust() |>
  DB.delete()`. The grant rows the answer rests on are held until
  the delete commits, so a revocation of one of them lands after the delete, and a grant made
  meanwhile is not seen - the delete is refused where a moment later it would pass. Every related
  row a rule reads - a `via:` target, or a row along a path - is held the same way, so a change to
  it lands after the delete. Code outside a session deletes raw.

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

  In a session, the delete is evaluated against the session user's policies for :delete, an
  anonymous session's for a signed-out visitor, against the row as it stands, read FOR UPDATE, and
  raises Hologram.AccessDeniedError when no
  rule grants it. The grant rows the answer rests on are held until the delete commits, so a
  revocation of one of them lands after the delete, and a grant made meanwhile is not seen - the
  delete is refused where a moment later it would pass. Every related row a rule reads - a `via:`
  target, or a row along a path - is held the same way, so a change to it lands after the delete.
  An entity claiming the server's own authority through trust/1 is deleted without evaluation, and
  code outside a session deletes raw without a claim. A struct whose id names no row is not
  evaluated at all: there is nothing to authorize against.

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
  restriction takes delete/1. A denied write raises Hologram.AccessDeniedError from either.
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

  The name is `<source table>_<relationship>_$join`. Past PostgreSQL's 63-byte limit the source
  table's name is dropped, its outer parts first, and a short hash goes between the relationship
  and `$join`. The table has the columns `source_id` and `target_id`. The `$` means it has to be
  quoted in SQL. The name follows the model: renaming the entity type or the relationship moves
  it, so code that asks for it keeps working where a name written out would break.

  Raises Hologram.MisuseError when the first argument is not an entity type module, or when the
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
      nil -> raise MisuseError, message: join_table_refusal(entity_type, relationship)
    end
  end

  @doc """
  Reads the given query from the database and returns its result - a list of entity
  structs for set queries, an entity struct or nil for single-result queries, and an
  integer for counting queries.

  The query is an entity type module (the whole entity set) or a query term built with
  Hologram.Query stages, holding the values it compares with. A derived field's query raises
  Hologram.MisuseError, since it is read through its field.

  A :string ordering reads the attribute's sort-key companion column, which every
  :string attribute derives.

  In a session - a Hologram page, command or middleware, or a job run as the user who created it -
  the query is read through the session user's :read policies, an anonymous session's for a
  signed-out visitor: the rows the policies grant, each included relationship filtered by its
  own type's :read rules, a
  single-result query answering nil and a counting query counting only what the user may read -
  exactly as a template's derived query is. A session user id no user entity can have - an
  app's own serial id - reads as an anonymous session would. Code outside a session reads
  raw: the trusted tier, for seeds, Mix tasks, a console and an app's own plugs and controllers.

  A query marked with trust/1 is read raw in a session too, signed in or not - the server's own
  authority, the spelling for a read that must see past the acting user's policies.
  """
  @spec read(module | Query.t()) :: list(Entity.t()) | Entity.t() | integer | nil
  def read(query) do
    term = Stage.normalize(query)

    assert_not_sourced!(term)

    result =
      if term.trust or not Context.session?() do
        QueryRunner.run(term, mapping())
      else
        QueryRunner.run_policied(term, mapping(), Context.actor_user_id())
      end

    if Process.get(@strip_server_only_key) do
      Entity.strip_server_only_deep(result)
    else
      result
    end
  end

  @doc """
  Returns the entity of the given type with the given id, or nil when no row matches -
  read/1 with one more predicate and single-result cardinality. Column values are decoded
  back into their logical types.

  In a session, the row is read through the session user's :read policies, an anonymous session's
  for a signed-out visitor, and a row the policies withhold reads as nil - as if it did not exist,
  which is what the template tier and the client answer. Code outside a session reads the row
  raw. A by-id read carries no claim, so a trusted one is
  `type |> filter(id: ^id) |> one() |> trust() |> DB.read()`.

  Raises Hologram.MisuseError when the id is not an entity id (a string of 22 base62
  characters), or when the first argument is not an entity type module.
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
  Hologram.MisuseError when called outside of a transaction.
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
  every table has `id`, `created_at`, `updated_at`, `server_created_at`, `server_updated_at`,
  `server_created_seq` and `server_updated_seq`, and a join table has `source_id` and `target_id`. Columns whose names contain `$` are the
  framework's own, and what they hold can change between versions. Select attributes by name.

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

  A uuid column or uuid array comes back in the 36-character lowercase 8-4-4-4-12 form, since
  PostgreSQL can't tell an entity id from another system's UUID - Hologram.Entity.uuid_to_id/1
  gives the entity id spelling, to compare with an entity's id. A uuid parameter or uuid array
  parameter takes either spelling, an entity id or the 36-character form, and a 16-byte binary
  passes through. The conversion goes by the types PostgreSQL reports for the statement, so a text
  column holding a uuid-shaped string stays as it is. Other
  types arrive as the driver decodes them: `int8` as an integer, `float8` as a float, `text` as a
  string, `boolean`, `date` as a Date, `time` as a Time, `timestamptz` as a DateTime, an enum as
  its label string and `jsonb` as a map.

  `server_created_seq` and `server_updated_seq` come back as stored, and a stored number may not be
  final yet, so take a cursor or a read marker from a query, which hides a number until it is.

  Inside an enclosing transaction the statement runs on the transaction's connection and sees its
  uncommitted rows, and the transaction stays writable afterwards.

  A transaction-level advisory lock (`pg_advisory_xact_lock`, and its `_shared` and `pg_try_`
  variants) named in the statement is held until the enclosing transaction ends, or until the
  nested transaction it was taken in rolls back. A lock taken inside a function of the app's own
  isn't seen and is given back when the read returns. A statement that names one keeps everything
  else a read-only transaction allows it to do, such as changing a setting with `set_config` or
  calling `pg_notify`, so keep it to the lock. The wait for the lock counts against `timeout:` and
  against the time the enclosing transaction has left. Past `timeout:` the read is answered as
  {:error, %Hologram.SQLError{code: :query_canceled}}. Past the transaction's bound the driver
  closes the connection, the call raises DBConnection.ConnectionError and the transaction is lost.
  So take the lock first in the transaction, with a `timeout:` shorter than the time the transaction
  has left, or use `pg_try_advisory_xact_lock`, which never waits. Use a single-number key: the data
  layer locks rows with two-number keys.

  Runs only on the server: a page whose client code reaches it fails the build. Call it from a
  command, a job, a seed or a script, and hand an action what the client needs. A row is not an
  entity, so nothing strips server-only attribute values from it - a selected `password_hash` put
  in state reaches the client. Select what the client may see.

  The one option is `timeout:`, the milliseconds the statement may run as a positive integer up
  to 2_147_483_647, the largest PostgreSQL accepts, or `:infinity` - fifteen seconds by default.
  PostgreSQL enforces it: past it the statement is cancelled and answered as
  {:error, %Hologram.SQLError{code: :query_canceled}}, and the connection and any enclosing
  transaction carry on. Inside an enclosing transaction its own bound applies as well, and passing
  it closes the connection (see transaction/2). The read is not run again when PostgreSQL resolves
  a deadlock: it takes no row locks, and a deadlock over an advisory lock it waits for is answered
  as {:error, %Hologram.SQLError{code: :deadlock_detected}}, for whoever opened the enclosing
  transaction to retry.

  Raises Hologram.MisuseError for a statement that takes a session-level advisory lock or prepares a
  named statement, either of which would outlive the read on a pooled connection, for one that
  releases an advisory lock, which the read could not undo, and for one that takes a
  transaction-level advisory lock outside a transaction, where the lock would end with the read.
  Raises it as well for an option other than `timeout:`, an invalid timeout, a number of
  params that differs from the statement's placeholders, and a param that does not fit its
  placeholder's type. None of these runs the statement.
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

  Raises Hologram.MisuseError when the argument is not an entity type module.
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
  violations} or raises through its bang, and the transaction stays usable. In the browser only
  the server judges the value a counter move lands on, so a move past a bound still answers :ok,
  as update/1 says. An exception rolls the transaction back and re-raises. A write verb called
  inside it is not run again when PostgreSQL aborts the transaction as a deadlock victim - the
  error propagates, and this transaction is the one to retry.

  The `timeout:` option is the milliseconds from this call until the transaction has to be done,
  the wait for a free connection included, or `:infinity`, and is fifteen seconds by default. Past
  it the driver closes the connection, the running statement raises DBConnection.ConnectionError
  and the transaction is lost. A nested call's `timeout:` is ignored, since the outermost
  transaction's bound is the one that applies.

  A nested call costs two statements (SAVEPOINT and RELEASE, three when it rolls back), and
  PostgreSQL caches 64 subtransactions per session - a transaction opening more than that, such
  as a loop of writes inside one transaction, slows every other session's visibility checks for
  as long as it runs. Split such batches into transactions of their own.

  An Ecto repo runs on a connection pool of its own, so its transactions and the data layer's
  commit separately. Any data layer call that runs a statement raises Hologram.MisuseError while
  one of the app's Ecto repos has a transaction open in the calling process, reads included. A
  transaction Ecto's SQL sandbox holds for a test doesn't count.

  An Ecto query run inside this function makes the transaction fail with Hologram.MisuseError
  naming the query, at the next data layer statement, at a rollback, or when the function
  returns, and the data layer's writes roll back. Ecto can't be stopped at the call, so what it
  wrote may already be committed. An exception the function raises itself propagates unchanged.
  Keep every Ecto call outside the transaction: one made in another process isn't seen, nor is one
  that overrides its telemetry event, and a preload of several associations may or may not be
  caught, because Ecto runs it in parallel tasks when more than one association needs a query.
  """
  @spec transaction((-> any), keyword) :: {:ok, any} | {:error, any}
  defdelegate transaction(fun, opts \\ []), to: Connection

  @doc """
  Updates the entity of the given type with the given id, setting exactly the changed
  columns plus updated_at, server_updated_at and server_updated_seq - there is no full-row
  variant. Changes (a map or keyword list) are keyed by declared attribute names and to-one
  reference fields
  (`<relationship name>_id`) - a to-one reference is set, reassigned, or cleared (nil) through
  its reference field. Changing any other name, system attributes and the attributes the framework
  sets on a job included, raises Hologram.MisuseError - as do empty changes and an id that names no
  entity.

  Returns :ok, or {:error, violations} - the map Entity.validate/2 returns, naming each
  field the changes leave breaking a declaration: the declared constraints a changed value
  breaks (type, enum values, the required-nil rule, the constraint options), :unique for a
  changed unique
  attribute whose new value another row already holds or a changed unique to-one reference
  whose new target another row already references, {:unique, fields} for a key declared with
  unique that the changes leave the row sharing with another row, and :not_found for a changed
  to-one reference whose target row does not exist. A key's reason sits on every field of the
  key, the ones the update left alone among them, since the key is the changed values beside
  the ones the row keeps. A row's own current value never conflicts with itself. Values are
  judged before any SQL runs, and a write is attempted only once they pass. Uniqueness and
  reference existence are reported by the write itself for the constraint it refuses, and
  asked advisorily for every changed unique attribute, every key a change touches and every
  changed to-one reference the write did not answer for - an advisory answer describes the
  moment it was asked, and a value free then can be taken by the next attempt. A write refuses
  at the first violated database constraint and reports no other of its own.

  The misuses named above raise rather than returning, as does a constraint violation the
  mapping does not explain.

  In a session, the update is evaluated against the session user's update rules, an anonymous
  session's for a signed-out visitor, against the row as it stands, read FOR UPDATE: every field it
  changes - a reference field counting as its
  relationship - has to be covered by a rule that holds, a field-limited line covering it (one whose
  `only:` lists it, or whose `except:` leaves it out) or a line covering the whole row, and
  Hologram.AccessDeniedError names the fields none covers. Naming the row by type and id carries no
  claim, so a trusted update is a struct from a trusted read, `|> put_attribute(...) |> trust() |>
  DB.update()`. The grant rows the answer rests on are held
  until the update commits, so a revocation of one of them lands after the update, and a grant made
  meanwhile is not seen - the update is refused where a moment later it would pass. Every related
  row a rule reads - a `via:` target, or a row along a path - is held the same way, so a change to
  it lands after the update. Code outside a session updates raw.

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

  Only recorded changes are written: a field set directly on the struct is not among them, and a
  struct carrying nothing recorded raises Hologram.MisuseError, as do an id that names no entity
  and a change to an attribute the framework sets on a job, whatever the claim.
  The attribute changes go first and the edges follow, so a refused value leaves the edges unapplied
  and an edge that raises takes the values with it.

  In a session, the write is evaluated against the session user's update rules, an anonymous
  session's for a signed-out visitor, and raises Hologram.AccessDeniedError when no rule grants it.
  Every field it changes - a value put or moved,
  a to-one's reference field as its relationship, an edge as its to-many relationship - has to be
  covered by an update rule that holds: a field-limited line covering it (one whose `only:` lists
  it, or whose `except:` leaves it out) or a line covering the whole row. The refusal names the
  fields none covers. The row is read FOR UPDATE first and the rules are evaluated against it as it
  stands, before the recorded changes apply, so a rule describing the state a change leaves ("an
  editor may pin a note that is not pinned") reads the way it reads in a template. Nothing can
  change the row between the evaluation and the write, and the grant rows the answer rests on are
  held until the write commits, so a revocation of one of them lands after the write, and a grant
  made meanwhile is not seen - the write is refused where a moment later it would pass. Every
  related row a rule reads - a `via:` target, or a row along a path - is held the same way, so a
  change to it lands after the write. An entity claiming the server's own authority through trust/1
  is written without evaluation, and code outside a session writes raw without a claim.

  An update PostgreSQL aborts as a deadlock victim - its holds crossing another transaction's
  locks - is run again and answers the way it would have a moment later, a refusal included.
  Inside a caller's transaction the deadlock error propagates instead, and the caller's
  transaction is the one to retry.

  Returns {:error, violations} for a refused value exactly as update/3 does. A moved attribute is
  judged on the value the write leaves, so a move that would cross a declared bound is reported
  the same way. In the browser only the server can judge that value: the call answers :ok and the
  move applies at once, and if the server refuses it, all of the action's writes roll back.
  """
  @spec update(Entity.t()) :: :ok | {:error, %{atom => list(atom | {atom, any})}}
  def update(entity) when is_struct(entity) do
    Validator.validate_writable!(entity.__struct__)

    Writer.update(entity)
  end

  @doc """
  Like update/1, raising Hologram.WriteError instead of returning {:error, ...}.

  The spelling for seeds, scripts and fixtures, as create!/1 is - code that acts on a conflict
  takes update/1. A denied write raises Hologram.AccessDeniedError from either.
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
  The mapping is derived once at boot and cached for the lifetime of the runtime. Raises while the
  data model is under a hold (see `Hologram.Entity.Model.ensure_released!/0`).
  """
  @spec mapping() :: %{module => %{atom => any}}
  def mapping do
    Model.ensure_released!()

    :persistent_term.get(@mapping_key)
  end

  @doc """
  Returns the key of the persistent term holding the mapping.
  """
  @spec mapping_key() :: any
  def mapping_key, do: @mapping_key

  @doc """
  Applies the session settings every pool connection runs with to the given connection, and
  returns :ok - the pool's after_connect.

  The server keepalives and user timeout (see Hologram.DB.Config.keepalive_statement/0). A node
  that vanishes leaves its sessions open on the server until the operating system there notices,
  and a session caught claiming a job holds that job's row locked meanwhile, so no other node can
  claim it.

  Best effort: a server refusing them - one compatible with PostgreSQL that lacks a setting - is
  warned about (see Hologram.DB.Config.warn_keepalives_refused/1) and the connection used as it
  is. Raising would leave the pool without a connection it could use, for good.
  """
  @spec apply_session_settings(DBConnection.conn()) :: :ok
  def apply_session_settings(connection) do
    case Postgrex.query(connection, Config.keepalive_statement(), []) do
      {:ok, _result} ->
        :ok

      # The connection is gone, which the pool logs, and its replacement runs this again.
      {:error, %DBConnection.ConnectionError{}} ->
        :ok

      {:error, error} ->
        Config.warn_keepalives_refused(error)
    end
  end

  @doc """
  Returns :ok once the database answers through the current connection, trying again while it
  cannot be reached yet, with a warning for each try that failed.

  What the boot steps that need the database run first. A database that is away while the node
  boots - started alongside it, or restarting - holds the boot until it is back, the way the pool
  itself keeps trying, rather than failing it: a boot step that fails fails the application.

  A pool tells only that it has no connection to give, which a server that is down and settings
  that are wrong look the same through. So a failed try opens one connection of its own to learn
  which: a server that refuses or cannot be reached - a host name that does not resolve included -
  or one still starting up or shutting down, is waited for. Any other error - a wrong password, a
  database that does not exist, a connection limit, a TLS handshake refused over a certificate -
  the client's included - or over the TLS options - raises, failing the boot as it did before the
  wait. A TLS handshake that times out or is closed is waited for. In dev, a database that does not
  exist raises naming mix holo.db.reset, which creates it. An error the query itself answers with
  raises the same way, unless it is one of those.

  It runs inside the start of the database's supervisor, so a restart of that supervisor while the
  database is away - rare, since the pool waits rather than failing - holds the unit above it, and
  an application stop meanwhile, until the database is back.

  Options:

    * `:connection_opts` - the Postgrex options the connection of its own opens with, defaulting to
      the configured database's (see Hologram.DB.Config.connection_opts/1), which is what the pool
      started at boot reaches.

    * `:retry_interval_ms` - how long to wait between two tries, defaulting to 2 seconds.
  """
  @spec await_database(keyword) :: :ok
  def await_database(opts \\ []) do
    retry_interval_ms = Keyword.get(opts, :retry_interval_ms, @await_retry_interval_ms)

    case Connection.query("SELECT 1") do
      {:ok, _result} ->
        :ok

      {:error, %DBConnection.ConnectionError{}} ->
        opts
        |> Keyword.get_lazy(:connection_opts, &Config.connection_opts/0)
        |> probe_database!()
        |> warn_unreachable(retry_interval_ms)

        Process.sleep(retry_interval_ms)

        await_database(opts)

      {:error, %Postgrex.Error{postgres: %{code: code}} = error}
      when code in @unavailable_error_codes ->
        warn_unreachable(error, retry_interval_ms)

        Process.sleep(retry_interval_ms)

        await_database(opts)

      {:error, error} ->
        raise error
    end
  end

  @doc """
  Runs the migration applier as a one-shot supervision child after the pool starts and
  returns :ignore (no process stays running). Waits for the database first (see
  await_database/1). A failed apply fails the boot loudly.
  """
  @spec migrate_at_boot() :: :ignore
  def migrate_at_boot do
    await_database()
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
  and returns :ignore (no process stays running). Waits for the database first (see
  await_database/1). A failed reconciliation fails the boot loudly.
  """
  @spec reconcile_at_boot() :: :ignore
  def reconcile_at_boot do
    await_database()
    reconcile_with_plan(reconciliation_context())

    :ignore
  end

  @doc """
  Returns the context for a schema reconciliation run: the cached mapping, the index plan
  over it (see `Hologram.DB.IndexPlan.plan/2`), the guard facts (otp_app and env as strings),
  and the marker diagnostics (the Hologram version and the current UTC timestamp).
  """
  @spec reconciliation_context() :: %{atom => any}
  def reconciliation_context do
    mapping = mapping()

    %{
      mapping: mapping,
      plan: IndexPlan.plan(mapping),
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
    |> Enum.flat_map(fn
      {field, :unique} ->
        [
          "  * #{unique_kind(entity_type, field)} #{inspect(field)}#{given_value(values, field)} is already taken"
        ]

      # Every field of a taken key carries the reason, and the key is one thing to say: its line
      # is written once, in the place of the first of its fields.
      {field, {:unique, fields}} ->
        if field == Enum.min(fields), do: [key_refusal_line(fields, values)], else: []

      {field, :not_found} ->
        [
          "  * reference #{inspect(field)} #{inspect(Map.fetch!(values, field))} names no existing entity"
        ]

      violation ->
        [Validator.violation_description(entity_type, values, violation)]
    end)
    |> Enum.join("\n")
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

      reconcile_with_plan(reconciliation_context())
    end

    :ok
  end

  @doc """
  Reconciles the schema again when the index plan the build's dump gives now differs from the one
  this node last converged the database to - the live-reload path once a compile has derived or
  kept the data layer, since a change to a query alone changes the plan without touching the model. A no-op
  when the database is not running. Returns :ok.
  """
  @spec reload_indexes() :: :ok
  def reload_indexes do
    if Process.whereis(__MODULE__) do
      context = reconciliation_context()

      if context.plan != :persistent_term.get(@plan_key, nil) do
        reconcile_with_plan(context)
      end
    end

    :ok
  end

  # Runs the function with every read/1 and read/2 it makes returning its rows with their
  # server-only attributes replaced by placeholders. The renderer runs templates and derived
  # functions through it: a row one reads itself would otherwise reach the HTML with values the
  # browser never gets. A call inside another leaves the outer one's setting as it was.
  @doc false
  @spec with_server_only_stripped((-> result)) :: result when result: any
  def with_server_only_stripped(fun) do
    outer = Process.put(@strip_server_only_key, true)

    try do
      fun.()
    after
      if outer do
        Process.put(@strip_server_only_key, outer)
      else
        Process.delete(@strip_server_only_key)
      end
    end
  end

  @doc """
  Starts the database: derives and caches the mapping, then starts the connection pool -
  in dev, schema reconciliation runs as a one-shot boot step right after the pool is up,
  and outside dev and test the migration applier runs there instead.
  The given opts override the resolved connection options - the test helper's ownership pool
  among them, and :after_connect, which replaces the session settings rather than adding to them
  (see apply_session_settings/1). The database is a VM-wide
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

    # The driver boundary - Config.postgrex_opts/1 turns the resolved config into Postgrex's
    # options, ssl included. Given opts win, so that tests can inject overrides (e.g. an
    # ownership pool).
    postgrex_opts =
      Keyword.merge(
        Config.postgrex_opts(resolved_opts) ++
          [
            after_connect: {__MODULE__, :apply_session_settings, []},
            name: @pool_name,
            pool_size: resolved_opts[:pool_size]
          ],
        opts
      )

    # TODO(#1696): {Postgrex, postgrex_opts} again, see Hologram.DB.Protocol.
    pool_child = {Protocol, postgrex_opts}

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

  # A derived field's query reads a set reached from a row of its owning type, and compares with
  # that row's fields - read alone it has no row to start from.
  defp assert_not_sourced!(%Query{source: {owner, chain}}) do
    raise MisuseError,
      message:
        "cannot read a derived field's query on its own - it reads #{Enum.join(chain, ".")} of a #{inspect(owner)} row, so it is read through the derived field"
  end

  defp assert_not_sourced!(_term), do: :ok

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

  defp reconcile_with_plan(context) do
    SchemaReconciler.reconcile(context)
    :persistent_term.put(@plan_key, context.plan)
  end

  # The value the write gave the field, ahead of which it is spelled - or nothing, for a field
  # an update moved by an amount: the write names no value for it, the row does.
  defp given_value(values, field) do
    case Map.fetch(values, field) do
      {:ok, value} -> " #{inspect(value)}"
      :error -> ""
    end
  end

  # The values are the ones the write gave: an update gives only its changes, so the fields of
  # the key it left alone or moved by an amount are named by the key and not spelled out.
  defp key_refusal_line(fields, values) do
    given =
      fields
      |> Enum.filter(&Map.has_key?(values, &1))
      |> Enum.map_join(", ", &"#{&1} #{inspect(Map.fetch!(values, &1))}")

    given_part = if given == "", do: "", else: " (#{given})"

    "  * key #{inspect(fields)} is already taken#{given_part}"
  end

  # Opens a connection of its own to learn why the pool has none to give. Returns the error of a
  # database that is away, or nil when this one connected - the pool's own connections are then
  # still waiting out their backoff. Raises any other error.
  defp probe_database!(connection_opts) do
    case ProbeConnection.start(connection_opts) do
      {:ok, pid} ->
        ProbeConnection.stop(pid)

        nil

      {:error, %DBConnection.ConnectionError{message: message} = error} ->
        if tls_misconfiguration?(message), do: raise(error), else: error

      {:error, %Postgrex.Error{postgres: %{code: code}} = error}
      when code in @unavailable_error_codes ->
        error

      {:error, %Postgrex.Error{postgres: %{code: :invalid_catalog_name}} = error} ->
        raise_missing_database!(error, connection_opts[:database])

      {:error, error} ->
        raise error
    end
  end

  # A TLS handshake the server or the client refused - an alert, like a certificate no CA given
  # trusts or a host name it doesn't cover - or TLS options the client refused, like a CA file
  # that doesn't exist. Either fails the same way on every try. A handshake that timed out or was
  # closed is a server that is away. Under TLS 1.3 the connect returns before the server checks
  # the client's certificate, so the server's refusal of it comes as an alert on the first read,
  # as "ssl recv (idle): ...", not on the connect. Postgrex gives the reason only inside the
  # message, as "ssl <action>: <formatted reason> - <inspected reason>", so the match is on that.
  defp tls_misconfiguration?(message) do
    String.starts_with?(message, "ssl ") and
      String.contains?(message, [" - {:tls_alert, ", " - {:options, "])
  end

  # In dev the reset creates the database along with Hologram's tables, so the error names it.
  # A test run makes its own database, and every other env's is the deploy's to create, so the
  # reset is no way out there.
  defp raise_missing_database!(error, database) do
    if Hologram.env() == :dev do
      raise ~s(database "#{database}" does not exist - create it, or run mix holo.db.reset to ) <>
              "create it with Hologram's tables"
    end

    raise error
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
      raise MisuseError, message: "#{inspect(term)} is not an entity type module - #{hint}"
    end

    :ok
  end

  # A job's create means more than storing a row - it schedules work to run after the transaction
  # commits - so it has one spelling, the way a role grant has one. The message gives the reason
  # rather than the redirect, since the two verbs are now the same word in different modules.
  defp validate_not_job!(entity_type) do
    if Reflection.job?(entity_type) do
      raise MisuseError,
        message:
          "#{inspect(entity_type)} is a job type - create it through Job.create/2, which records who enqueued it so the worker can run it as them after the transaction commits"
    end

    :ok
  end

  defp warn_unreachable(nil, retry_interval_ms) do
    Logger.warning(
      "the database answers, but the pool has not connected to it yet, trying again in #{retry_interval_ms} ms"
    )
  end

  defp warn_unreachable(error, retry_interval_ms) do
    Logger.warning(
      "the database cannot be reached yet, trying again in #{retry_interval_ms} ms: #{Exception.message(error)}"
    )
  end
end
