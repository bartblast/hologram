defmodule Hologram.Database do
  @moduledoc false

  use Supervisor

  alias Hologram.Database.Config
  alias Hologram.Database.Connection
  alias Hologram.Database.EntityOperations
  alias Hologram.Database.Mapper
  alias Hologram.Database.SchemaReconciler
  alias Hologram.Reflection

  @mapping_key {__MODULE__, :mapping}

  @pool_name Hologram.Database.Pool

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
  stamping created_at and updated_at with the same current UTC timestamp. Returns the
  stamped entity. Constraint violations raise.
  """
  @spec create(struct) :: struct
  defdelegate create(entity), to: EntityOperations

  @doc """
  Deletes the entity of the given type with the given id together with its own outgoing
  to-many edges, in one transaction. An incoming reference from another entity - a
  to-one reference column or an edge pointing at this entity - restricts the delete,
  returning {:error, {:restricted, %{entity_type: entity_type, id: id}}} with nothing
  deleted. This is the one translated constraint error - any other constraint violation
  raises. Deleting a nonexistent id is a no-op. Returns :ok.
  """
  @spec delete(module, String.t()) :: :ok | {:error, {:restricted, map}}
  defdelegate delete(entity_type, id), to: EntityOperations

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
  """
  @spec get(module, String.t()) :: struct | nil
  defdelegate get(entity_type, id), to: EntityOperations

  @doc """
  Executes the given SQL statement with the given params and returns {:ok, result} or
  {:error, exception}. Inside transaction/2 the statement runs on the transaction's
  connection, otherwise on the pool.
  """
  @spec query(String.t(), list, keyword) :: {:ok, Postgrex.Result.t()} | {:error, Exception.t()}
  defdelegate query(statement, params \\ [], opts \\ []), to: Connection

  @doc """
  Aborts the enclosing transaction/2, making it return {:error, reason}. Raises
  ArgumentError when called outside of a transaction.
  """
  @spec rollback(any) :: no_return
  defdelegate rollback(reason), to: Connection

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
  id that names no entity. Returns :ok. Constraint violations raise.
  """
  @spec update(module, String.t(), map | keyword) :: :ok
  defdelegate update(entity_type, id, changes), to: EntityOperations

  @doc """
  Returns the physical name mapping derived from the discovered entity type modules.
  The mapping is derived once at boot and cached for the lifetime of the runtime.
  """
  @spec mapping() :: %{module => %{atom => any}}
  def mapping do
    :persistent_term.get(@mapping_key)
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
  in dev, schema reconciliation runs as a one-shot boot step right after the pool is up.
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

    children =
      if Hologram.env() == :dev do
        [pool_child, %{id: :schema_reconciliation, start: {__MODULE__, :reconcile_at_boot, []}}]
      else
        [pool_child]
      end

    Supervisor.init(children, strategy: :one_for_one)
  end
end
