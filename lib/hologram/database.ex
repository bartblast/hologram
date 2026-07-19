defmodule Hologram.Database do
  @moduledoc false

  # TODO: split the internals into dedicated modules along the substrate/primitives seam
  # (connection/transaction machinery vs entity row operations) once all primitives exist -
  # the public surface stays on this module, and test files then match module files.

  use Supervisor

  alias Hologram.Database.Codec
  alias Hologram.Database.Config
  alias Hologram.Database.Mapper
  alias Hologram.Reflection

  @data_schema "hologram_data"

  @mapping_key {__MODULE__, :mapping}

  @pool_name Hologram.Database.Pool

  @sandbox_rollback_throw {__MODULE__, :sandbox_rollback}

  @sandbox_savepoint "hologram_transaction"

  @transaction_key {__MODULE__, :transaction}

  @doc """
  Inserts the given entity as a full row - every column is named and bound explicitly -
  stamping created_at and updated_at with the same current UTC timestamp. Returns the
  stamped entity. Constraint violations raise.
  """
  @spec create(struct) :: struct
  def create(entity) do
    entity_type = entity.__struct__
    %{table: table, columns: columns} = Map.fetch!(mapping(), entity_type)

    now = DateTime.utc_now(:microsecond)
    stamped_entity = %{entity | created_at: now, updated_at: now}

    encoded_values =
      Enum.map(columns, fn column ->
        stamped_entity
        |> Map.fetch!(field_name(column))
        |> Codec.encode(column.type)
      end)

    column_list = Enum.map_join(columns, ", ", &Mapper.quote_identifier(&1.name))
    placeholder_list = Enum.map_join(1..length(columns), ", ", &"$#{&1}")

    statement =
      "INSERT INTO #{qualified_table(table)} (#{column_list}) VALUES (#{placeholder_list})"

    case query(statement, encoded_values) do
      {:ok, _result} -> stamped_entity
      {:error, error} -> raise error
    end
  end

  @doc """
  Marks the calling process as running inside an externally managed transaction (the test
  sandbox): queries route to the pool as usual, transaction/2 emulates the outermost
  transaction with a savepoint instead of issuing BEGIN/COMMIT, and rollback/1 rolls back
  to that savepoint - so the externally managed transaction itself is never committed or
  aborted.
  """
  @spec enter_sandbox() :: :ok
  def enter_sandbox do
    Process.put(@transaction_key, {:sandbox, @pool_name})
    :ok
  end

  @doc """
  Returns the entity of the given type with the given id, or nil when no row matches.
  Column values are decoded back into their logical types.
  """
  @spec get(module, String.t()) :: struct | nil
  def get(entity_type, id) do
    %{table: table, columns: columns} = Map.fetch!(mapping(), entity_type)

    column_list = Enum.map_join(columns, ", ", &Mapper.quote_identifier(&1.name))
    statement = ~s|SELECT #{column_list} FROM #{qualified_table(table)} WHERE "id" = $1|

    encoded_id = Codec.encode(id, :uuid)

    case query(statement, [encoded_id]) do
      {:ok, %Postgrex.Result{rows: []}} ->
        nil

      {:ok, %Postgrex.Result{rows: [row]}} ->
        fields =
          columns
          |> Enum.zip(row)
          |> Enum.map(fn {column, value} ->
            {field_name(column), Codec.decode(value, column.type)}
          end)

        struct!(entity_type, fields)

      {:error, error} ->
        raise error
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
  Returns the name of the connection pool process.
  """
  @spec pool_name() :: atom
  def pool_name do
    @pool_name
  end

  @doc """
  Executes the given SQL statement with the given params and returns {:ok, result} or
  {:error, exception}. Inside transaction/2 the statement runs on the transaction's
  connection, otherwise on the pool.
  """
  @spec query(String.t(), list, keyword) :: {:ok, Postgrex.Result.t()} | {:error, Exception.t()}
  def query(statement, params \\ [], opts \\ []) do
    Postgrex.query(current_connection(), statement, params, opts)
  end

  @doc """
  Aborts the enclosing transaction/2, making it return {:error, reason}. Raises
  ArgumentError when called outside of a transaction.
  """
  @spec rollback(any) :: no_return
  def rollback(reason) do
    case Process.get(@transaction_key) do
      {:transaction, connection} ->
        Postgrex.rollback(connection, reason)

      {:sandbox_transaction, _pool_name} ->
        throw({@sandbox_rollback_throw, reason})

      _other ->
        raise ArgumentError, "cannot rollback - not inside a transaction"
    end
  end

  # The database is a VM-wide singleton - booting while an instance is already running
  # yields to the running instance instead of failing the caller's supervision tree.
  @spec start_link(keyword) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    case Supervisor.start_link(__MODULE__, opts, name: __MODULE__) do
      {:error, {:already_started, _pid}} -> :ignore
      other -> other
    end
  end

  @doc """
  Runs the given zero-arity function inside a database transaction and returns
  {:ok, result}. Transactions are flat: a nested call joins the ongoing transaction
  instead of nesting - there are no savepoints, and rollback/1 aborts the one flat
  transaction wherever it is called. An exception rolls the transaction back and
  re-raises.
  """
  @spec transaction((-> any), keyword) :: {:ok, any} | {:error, any}
  def transaction(fun, opts \\ []) do
    case Process.get(@transaction_key) do
      nil -> run_transaction(fun, opts)
      {:sandbox, pool_name} -> run_sandbox_transaction(fun, pool_name)
      {:transaction, _connection} -> {:ok, fun.()}
      {:sandbox_transaction, _pool_name} -> {:ok, fun.()}
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

    Supervisor.init([{Postgrex, postgrex_opts}], strategy: :one_for_one)
  end

  defp current_connection do
    case Process.get(@transaction_key) do
      nil -> @pool_name
      {:sandbox, pool_name} -> pool_name
      {:sandbox_transaction, pool_name} -> pool_name
      {:transaction, connection} -> connection
    end
  end

  defp field_name(%{source: :system, name: name}), do: String.to_existing_atom(name)

  defp field_name(%{source: {:attribute, name}}), do: name

  defp field_name(%{source: {:relationship, name}}), do: name

  defp qualified_table(table) do
    "#{Mapper.quote_identifier(@data_schema)}.#{Mapper.quote_identifier(table)}"
  end

  # Emulates the outermost transaction inside the externally managed sandbox transaction:
  # a savepoint stands in for BEGIN, so that commit/abort of the emulated transaction
  # never touches the sandbox transaction around it.
  defp run_sandbox_transaction(fun, pool_name) do
    Postgrex.query!(pool_name, "SAVEPOINT #{@sandbox_savepoint}", [])
    Process.put(@transaction_key, {:sandbox_transaction, pool_name})

    try do
      result = fun.()
      Postgrex.query!(pool_name, "RELEASE SAVEPOINT #{@sandbox_savepoint}", [])
      {:ok, result}
    rescue
      exception ->
        Postgrex.query!(pool_name, "ROLLBACK TO SAVEPOINT #{@sandbox_savepoint}", [])
        reraise exception, __STACKTRACE__
    catch
      :throw, {@sandbox_rollback_throw, reason} ->
        Postgrex.query!(pool_name, "ROLLBACK TO SAVEPOINT #{@sandbox_savepoint}", [])
        {:error, reason}
    after
      Process.put(@transaction_key, {:sandbox, pool_name})
    end
  end

  defp run_transaction(fun, opts) do
    Postgrex.transaction(
      @pool_name,
      fn connection ->
        Process.put(@transaction_key, {:transaction, connection})

        try do
          fun.()
        after
          Process.delete(@transaction_key)
        end
      end,
      opts
    )
  end
end
