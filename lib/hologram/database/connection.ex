defmodule Hologram.Database.Connection do
  @moduledoc false

  # The connection substrate of the database gateway: statement execution, the flat
  # transaction model, and the test sandbox mode. The public surface lives on
  # Hologram.Database - these functions back its delegates, which also carry the docs.

  alias Hologram.Database

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
    Process.put(@transaction_key, {:sandbox, Database.pool_name()})
    :ok
  end

  @doc false
  @spec query(String.t(), list, keyword) :: {:ok, Postgrex.Result.t()} | {:error, Exception.t()}
  def query(statement, params \\ [], opts \\ []) do
    Postgrex.query(current_connection(), statement, params, opts)
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
    case Process.get(@transaction_key) do
      nil -> run_transaction(fun, opts)
      {:sandbox, pool_name} -> run_sandbox_transaction(fun, pool_name)
      {:transaction, _connection} -> {:ok, fun.()}
      {:sandbox_transaction, _pool_name} -> {:ok, fun.()}
    end
  end

  defp current_connection do
    case Process.get(@transaction_key) do
      nil -> Database.pool_name()
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
      Database.pool_name(),
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
