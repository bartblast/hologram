defmodule Hologram.Database do
  @moduledoc false

  use Supervisor

  alias Hologram.Database.Config
  alias Hologram.Database.Mapper
  alias Hologram.Reflection

  @mapping_key {__MODULE__, :mapping}

  @pool_name Hologram.Database.Pool

  @sandbox_rollback_throw {__MODULE__, :sandbox_rollback}

  @sandbox_savepoint "hologram_transaction"

  @transaction_key {__MODULE__, :transaction}

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
