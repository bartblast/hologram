defmodule Hologram.DB.SQLQuery do
  @moduledoc false

  # The execution of an SQL read: one statement, prepared and run inside a read-only
  # subtransaction, answering Hologram's own result and error shapes. The public surface is on
  # Hologram.DB, which carries the docs.

  alias Hologram.DB
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.Entity.Validator
  alias Hologram.SQLError

  # The bound a statement runs under unless the caller gives one - the driver's own default, which
  # every other read of the layer runs under.
  @default_timeout 15_000

  # Both limits are local to the subtransaction, so its rollback takes them with it. One statement
  # sets both, one round trip.
  @limits_statement "SELECT set_config('transaction_read_only', 'on', true), " <>
                      "set_config('statement_timeout', $1, true)"

  # The type numbers PostgreSQL describes a uuid and a uuid array with - fixed in its catalog for
  # every version and every database, unlike the numbers of the types an app creates. The
  # conversion goes by these alone, never by a value's shape, so a text column holding something
  # uuid-shaped stays text and a 16-byte bytea stays bytes.
  @uuid_array_oid 2951

  @uuid_oid 2950

  # The function handed to the transaction always ends in a rollback, on purpose (see the comment
  # inside), which Dialyzer reports as a function with no local return.
  @dialyzer {:no_return, run: 3}

  @doc """
  Runs the given statement with the given params inside a read-only subtransaction and returns
  {:ok, result} with the columns and rows, or {:error, error} for a statement the server refused,
  cancelled or failed.

  The one option is :timeout, the milliseconds the statement may run as a positive integer, or
  :infinity - 15 seconds by default. The server enforces it.

  Raises ArgumentError for an unknown option, an invalid timeout, a param count that differs from
  the statement's placeholders, and a param the driver cannot send as its placeholder's type.
  """
  @spec run(String.t(), list, keyword) :: {:ok, DB.sql_result()} | {:error, SQLError.t()}
  def run(statement, params, opts) do
    statement_timeout = statement_timeout!(opts)

    # The savepoint is rolled back whether the read succeeded or failed. The rollback is what
    # takes the read-only setting with it: a released savepoint hands its settings to the
    # enclosing transaction, which could then write nothing, and PostgreSQL refuses to switch a
    # subtransaction back to read-write. A read leaves nothing to commit. A statement that
    # failed leaves the transaction in the failed state, where a commit answers {:error,
    # :rollback} and loses the error, so the outcome travels as the rollback's reason.
    #
    # A transaction this opens carries no driver deadline: the driver's fires by closing the
    # connection, and the statement timeout set inside is the bound, one that cancels the
    # statement alone. Inside a caller's transaction that transaction's own deadline applies.
    {:error, {:sql_query, outcome}} =
      Connection.transaction(
        fn ->
          {:ok, _result} = Connection.query(@limits_statement, [statement_timeout])
          Connection.rollback({:sql_query, prepare_and_execute(statement, params)})
        end,
        timeout: :infinity
      )

    outcome
  end

  defp decode_rows(rows, oids) do
    Enum.map(rows, fn row ->
      Enum.zip_with(row, oids, &decode_value/2)
    end)
  end

  defp decode_value(nil, _oid), do: nil

  defp decode_value(value, @uuid_oid), do: Codec.decode(value, :uuid)

  # A multidimensional array has the same type as a flat one and arrives as nested lists.
  defp decode_value(values, @uuid_array_oid) do
    Enum.map(values, fn
      nested_values when is_list(nested_values) -> decode_value(nested_values, @uuid_array_oid)
      value -> decode_value(value, @uuid_oid)
    end)
  end

  defp decode_value(value, _oid), do: value

  defp encode_params(params, oids) do
    Enum.zip_with(params, oids, &encode_value/2)
  end

  # A string that is not a canonical id goes to the driver untouched, which refuses it the way it
  # refuses a binary of the wrong size.
  defp encode_value(value, @uuid_oid) when is_binary(value) do
    if Validator.attribute_value_valid?(value, :uuid) do
      Codec.encode(value, :uuid)
    else
      value
    end
  end

  defp encode_value(values, @uuid_array_oid) when is_list(values) do
    Enum.map(values, fn
      nested_values when is_list(nested_values) -> encode_value(nested_values, @uuid_array_oid)
      value -> encode_value(value, @uuid_oid)
    end)
  end

  defp encode_value(value, _oid), do: value

  # A param the driver cannot encode never reaches the server - a mistake in the calling code,
  # raised as the layer raises its other misuses. The driver's sentence stays, since it is the one
  # that names the value and the type it expected.
  defp execute(query, params) do
    Connection.execute(query, params)
  rescue
    error in DBConnection.EncodeError ->
      reraise ArgumentError,
              [
                message:
                  "a param of DB.sql/3 does not fit the type of its placeholder in the statement " <>
                    "- #{Exception.message(error)}"
              ],
              __STACKTRACE__
  end

  defp prepare_and_execute(statement, params) do
    with {:ok, query} <- Connection.prepare(statement),
         :ok <- validate_param_count!(params, query.param_oids),
         encoded_params = encode_params(params, query.param_oids),
         {:ok, _query, result} <- execute(query, encoded_params) do
      {:ok, result(result, query.result_oids)}
    else
      {:error, exception} -> {:error, to_error(exception)}
    end
  end

  defp quantity(1, noun), do: "1 #{noun}"

  defp quantity(count, noun), do: "#{count} #{noun}s"

  defp read_only_message(server_message) do
    "DB.sql/3 can only read data, and this statement writes it (PostgreSQL: #{server_message}). " <>
      "Use DB.create/1, DB.update/3 or DB.delete/2 to write, so that the change reaches the sync " <>
      "and the clients."
  end

  # A statement with no result set, a SET LOCAL say, describes no columns and answers no rows.
  defp result(%Postgrex.Result{columns: nil}, _oids), do: %{columns: [], rows: []}

  defp result(%Postgrex.Result{columns: columns, rows: rows}, oids) do
    %{columns: columns, rows: decode_rows(rows, oids)}
  end

  # PostgreSQL reads 0 as no limit at all, so a timeout of 0 is refused rather than passed on: it
  # would mean the opposite of what it says.
  defp statement_timeout!(opts) do
    opts
    |> Keyword.keys()
    |> Enum.each(fn key ->
      if key != :timeout do
        raise ArgumentError,
          message: "unknown option #{inspect(key)} for DB.sql/3 - the one option is :timeout"
      end
    end)

    case Keyword.get(opts, :timeout, @default_timeout) do
      :infinity ->
        "0"

      timeout when is_integer(timeout) and timeout > 0 ->
        Integer.to_string(timeout)

      timeout ->
        raise ArgumentError,
          message:
            "invalid timeout #{inspect(timeout)} for DB.sql/3 - give a positive number of " <>
              "milliseconds or :infinity"
    end
  end

  defp to_error(%Postgrex.Error{postgres: %{code: :read_only_sql_transaction, message: message}}) do
    %SQLError{code: :read_only_sql_transaction, message: read_only_message(message)}
  end

  defp to_error(%Postgrex.Error{postgres: %{code: code, message: message}}) do
    %SQLError{code: code, message: message}
  end

  # A failure the server never answered, such as a lost connection.
  defp to_error(exception) do
    %SQLError{code: nil, message: Exception.message(exception)}
  end

  defp validate_param_count!(params, oids) do
    param_count = length(params)
    placeholder_count = length(oids)

    if param_count != placeholder_count do
      raise ArgumentError,
        message:
          "DB.sql/3 got #{quantity(param_count, "param")} for a statement with " <>
            quantity(placeholder_count, "placeholder")
    end

    :ok
  end
end
