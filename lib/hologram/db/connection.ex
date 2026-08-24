defmodule Hologram.DB.Connection do
  @moduledoc false

  # The connection substrate of the database gateway: statement execution, nested
  # transactions as savepoints, and the test sandbox mode. The public surface lives on
  # Hologram.DB - these functions back its delegates, which also carry the docs.

  alias Hologram.DB

  @connection_key {__MODULE__, :connection}

  @rollback_throw {__MODULE__, :rollback}

  @timeout_key {__MODULE__, :timeout}

  @transaction_key {__MODULE__, :transaction}

  @doc """
  Marks the calling process as running inside an externally managed transaction (the test
  sandbox): queries route to the pool as usual, transaction/2 emulates the outermost
  transaction with a savepoint instead of issuing BEGIN/COMMIT, and rollback/1 rolls back
  to that savepoint - so the externally managed transaction itself is never committed or
  aborted. Queries carry no driver timeout in this mode - the test framework's per-test
  timeout is the time bound.
  """
  @spec enter_sandbox() :: :ok
  def enter_sandbox do
    Process.put(@transaction_key, {:sandbox, DB.pool_name()})

    # The driver's fifteen second default is a second, lower bound under the per-test one,
    # and the worse of the two: it fires by killing the connection, which takes the
    # sandbox transaction and every row the test wrote with it, so the test fails later on
    # data that silently vanished. With no driver bound a stalled query gets its full
    # per-test window, and a genuine hang is ended by the test framework naming the test.
    Process.put(@timeout_key, :infinity)

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
      {:transaction, connection, 1} ->
        Postgrex.rollback(connection, reason)

      {:transaction, _connection, depth} ->
        throw({@rollback_throw, depth, reason})

      {:sandbox_transaction, _pool_name, depth} ->
        throw({@rollback_throw, depth, reason})

      _other ->
        raise ArgumentError, "cannot rollback - not inside a transaction"
    end
  end

  @doc false
  @spec transaction((-> any), keyword) :: {:ok, any} | {:error, any}
  def transaction(fun, opts \\ []) do
    opts = with_timeout_opt(opts)

    case Process.get(@transaction_key) do
      nil ->
        run_transaction(fun, opts)

      {:sandbox, pool_name} ->
        run_savepoint(fun, 1, {:sandbox_transaction, pool_name, 1})

      {:transaction, connection, depth} ->
        run_savepoint(fun, depth + 1, {:transaction, connection, depth + 1})

      {:sandbox_transaction, pool_name, depth} ->
        run_savepoint(fun, depth + 1, {:sandbox_transaction, pool_name, depth + 1})
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
      {:sandbox_transaction, pool_name, _depth} -> pool_name
      {:transaction, connection, _depth} -> connection
    end
  end

  defp restore_key(key, nil), do: Process.delete(key)

  defp restore_key(key, value), do: Process.put(key, value)

  defp rollback_savepoint(connection, savepoint) do
    Postgrex.query!(connection, "ROLLBACK TO SAVEPOINT #{savepoint}", [])
    Postgrex.query!(connection, "RELEASE SAVEPOINT #{savepoint}", [])
  end

  # A nested transaction is a savepoint named by its depth, the externally managed sandbox
  # transaction being depth 0. Each level rolls back its own savepoint and no other, which
  # is what lets a write verb's refusal return from the verb instead of unwinding the
  # caller's transaction with it.
  #
  # A rollback releases the savepoint as well: ROLLBACK TO leaves it defined, and a name
  # reused at the same depth hides the earlier savepoint rather than replacing it - so a
  # loop of refused writes inside one transaction would pile up a subtransaction per
  # refusal, against the 64 PostgreSQL caches per session, for as long as the transaction
  # ran.
  defp run_savepoint(fun, depth, mode) do
    connection = current_connection()
    outer_mode = Process.get(@transaction_key)
    savepoint = "hologram_#{depth}"

    Postgrex.query!(connection, "SAVEPOINT #{savepoint}", [])
    Process.put(@transaction_key, mode)

    try do
      result = fun.()
      Postgrex.query!(connection, "RELEASE SAVEPOINT #{savepoint}", [])
      {:ok, result}
    rescue
      exception ->
        rollback_savepoint(connection, savepoint)
        reraise exception, __STACKTRACE__
    catch
      :throw, {@rollback_throw, thrown_depth, reason} when thrown_depth == depth ->
        rollback_savepoint(connection, savepoint)
        {:error, reason}
    after
      Process.put(@transaction_key, outer_mode)
    end
  end

  defp run_transaction(fun, opts) do
    connection = Process.get(@connection_key, DB.pool_name())

    Postgrex.transaction(
      connection,
      fn connection ->
        Process.put(@transaction_key, {:transaction, connection, 1})

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
