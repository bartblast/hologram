defmodule Hologram.DB.SQLQuery do
  @moduledoc false

  # The execution of an SQL read: one statement, prepared and run inside a read-only
  # subtransaction, answering Hologram's own result and error shapes. The public surface is
  # Hologram.DB.sql/3, which carries the docs.

  alias Hologram.DB
  alias Hologram.DB.Connection
  alias Hologram.SQLError

  # The function run/3 hands the transaction always ends in a rollback, on purpose (see the
  # comment inside), which Dialyzer reports as a function with no local return.
  @dialyzer {:no_return, run: 3}

  @doc """
  Runs the given statement with the given params inside a read-only subtransaction and returns
  {:ok, result} with the columns and rows, or {:error, error} for a statement the server refused
  or that failed.

  The opts go to the driver's prepare and execute.
  """
  @spec run(String.t(), list, keyword) :: {:ok, DB.sql_result()} | {:error, SQLError.t()}
  def run(statement, params, opts) do
    # The savepoint is rolled back whether the read succeeded or failed. The rollback is what
    # takes the read-only setting with it: a released savepoint hands its settings to the
    # enclosing transaction, which could then write nothing, and PostgreSQL refuses to switch a
    # subtransaction back to read-write. A read leaves nothing to commit. A statement that
    # failed leaves the transaction in the failed state, where a commit answers {:error,
    # :rollback} and loses the error, so the outcome travels as the rollback's reason.
    {:error, {:sql_query, outcome}} =
      Connection.transaction(fn ->
        {:ok, _result} = Connection.query("SET LOCAL transaction_read_only = on")
        Connection.rollback({:sql_query, prepare_and_execute(statement, params, opts)})
      end)

    outcome
  end

  defp prepare_and_execute(statement, params, opts) do
    with {:ok, query} <- Connection.prepare(statement, opts),
         {:ok, _query, result} <- Connection.execute(query, params, opts) do
      {:ok, result(result)}
    else
      {:error, exception} -> {:error, to_error(exception)}
    end
  end

  defp read_only_message(server_message) do
    "DB.sql/3 can only read data, and this statement writes it (PostgreSQL: #{server_message}). " <>
      "Use DB.create/1, DB.update/3 or DB.delete/2 to write, so that the change reaches the sync " <>
      "and the clients."
  end

  # A statement with no result set, a SET LOCAL say, describes no columns and answers no rows.
  defp result(%Postgrex.Result{columns: columns, rows: rows}) do
    %{columns: columns || [], rows: rows || []}
  end

  defp to_error(%Postgrex.Error{postgres: %{code: :read_only_sql_transaction, message: message}}) do
    %SQLError{code: :read_only_sql_transaction, message: read_only_message(message)}
  end

  defp to_error(%Postgrex.Error{postgres: %{code: code, message: message}}) do
    %SQLError{code: code, message: message}
  end

  # A failure the server never answered - a timeout, a param the driver could not encode.
  defp to_error(exception) do
    %SQLError{code: nil, message: Exception.message(exception)}
  end
end
