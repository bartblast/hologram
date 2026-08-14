defmodule Hologram.DB.Connection do
  @moduledoc false

  # The connection substrate of the database gateway: statement execution, the flat
  # transaction model, and the test sandbox mode. The public surface lives on
  # Hologram.DB - these functions back its delegates, which also carry the docs.

  alias Hologram.DB

  @connection_key {__MODULE__, :connection}

  @sandbox_rollback_throw {__MODULE__, :sandbox_rollback}

  @sandbox_savepoint "hologram_transaction"

  @timeout_key {__MODULE__, :timeout}

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
    Process.put(@transaction_key, {:sandbox, DB.pool_name()})
    :ok
  end

  @doc false
  @spec query(String.t(), list, keyword) :: {:ok, Postgrex.Result.t()} | {:error, Exception.t()}
  def query(statement, params \\ [], opts \\ []) do
    Postgrex.query(current_connection(), statement, params, with_timeout_opt(opts))
  end

  @doc false
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

  @doc false
  @spec transaction((-> any), keyword) :: {:ok, any} | {:error, any}
  def transaction(fun, opts \\ []) do
    opts = with_timeout_opt(opts)

    case Process.get(@transaction_key) do
      nil -> run_transaction(fun, opts)
      {:sandbox, pool_name} -> run_sandbox_transaction(fun, pool_name)
      {:transaction, _connection} -> {:ok, fun.()}
      {:sandbox_transaction, _pool_name} -> {:ok, fun.()}
    end
  end

  @doc """
  Runs the given function with the calling process's queries and transactions routed to
  the given started connection instead of the pool, restoring the previous routing
  afterwards - a suspended sandbox mode included, so a sandboxed process can operate on
  another database and return to its sandbox transaction untouched. Nesting restores the
  enclosing routing rather than clearing it, so an inner connection cannot strand the
  outer one.
  """
  @spec with_connection(GenServer.server(), (-> any)) :: any
  def with_connection(connection, fun) do
    outer_mode = Process.get(@transaction_key)
    outer_connection = Process.get(@connection_key)

    Process.delete(@transaction_key)
    Process.put(@connection_key, connection)

    try do
      fun.()
    after
      restore_key(@connection_key, outer_connection)
      restore_key(@transaction_key, outer_mode)
    end
  end

  @doc """
  Runs the given function with the calling process's queries and transactions carrying
  the given timeout unless they name one of their own, restoring the previous default
  afterwards.

  For work whose duration is the database's to decide rather than the caller's - an index
  built over a large table, or a wait on a lock another node holds. The driver's default
  is fifteen seconds and it cancels the statement when that passes, which is a sane bound
  for a query serving a request and the wrong one for a deploy. Bounding these stays a
  server-side matter, through statement_timeout or lock_timeout.
  """
  @spec with_timeout(timeout, (-> any)) :: any
  def with_timeout(timeout, fun) do
    outer_timeout = Process.get(@timeout_key)
    Process.put(@timeout_key, timeout)

    try do
      fun.()
    after
      restore_key(@timeout_key, outer_timeout)
    end
  end

  defp current_connection do
    case Process.get(@transaction_key) do
      nil -> Process.get(@connection_key, DB.pool_name())
      {:sandbox, pool_name} -> pool_name
      {:sandbox_transaction, pool_name} -> pool_name
      {:transaction, connection} -> connection
    end
  end

  defp restore_key(key, nil), do: Process.delete(key)

  defp restore_key(key, value), do: Process.put(key, value)

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
    connection = Process.get(@connection_key, DB.pool_name())

    Postgrex.transaction(
      connection,
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

  defp with_timeout_opt(opts) do
    case Process.get(@timeout_key) do
      nil -> opts
      timeout -> Keyword.put_new(opts, :timeout, timeout)
    end
  end
end
