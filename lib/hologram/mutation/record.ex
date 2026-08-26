defmodule Hologram.Mutation.Record do
  @moduledoc false

  # One row per applied batch of client writes, keyed by the client that sent it and that
  # client's own sequence number - the primary key IS the dedup. The row is claimed first, inside
  # the batch's transaction and with no answer yet, so a second arrival of the same batch blocks
  # on the key until the first commits and then fails its own claim, and the answer is written
  # just before the commit.
  #
  # A refused batch's claim rolls back with everything else, so this table holds what happened
  # and a refusal did not happen. A claim with no answer therefore cannot be observed from
  # outside: it exists only inside the transaction holding it, which either commits with an
  # answer or takes the claim with it.
  #
  # The batch itself is not kept: the rows it wrote are in the effect log under mutation_ref,
  # keyed by the same pair, so keeping it here would keep every write twice.

  alias Hologram.DB.Codec
  alias Hologram.DB.Connection

  @doc """
  Claims the record for the given batch in the caller's transaction and returns :ok.

  Rolls the transaction back with :duplicate when the batch is already recorded - by an earlier
  arrival, or by a concurrent one that committed while this transaction was running. Such a batch
  is answered from its record rather than applied again.
  """
  @spec claim!(String.t(), non_neg_integer, String.t() | nil, String.t()) :: :ok
  def claim!(client_id, seq, actor_id, model_hash) do
    statement = """
    INSERT INTO "hologram_system"."mutation" ("client_id", "seq", "actor_id", "model_hash")
    VALUES ($1, $2, $3, $4)
    """

    params = [client_id, seq, Codec.encode(actor_id, :uuid), model_hash]

    case Connection.query(statement, params) do
      {:ok, _result} ->
        :ok

      # The statement aborted the transaction, so nothing further can run in it - and nothing
      # needs to: the batch is recorded, and its answer is what the caller owes.
      {:error, %Postgrex.Error{postgres: %{code: :unique_violation}}} ->
        Connection.rollback(:duplicate)

      {:error, error} ->
        raise error
    end
  end

  @doc """
  Records the answer the given batch got, in the caller's transaction, and returns :ok.
  """
  @spec complete!(String.t(), non_neg_integer, map) :: :ok
  def complete!(client_id, seq, result) do
    statement = """
    UPDATE "hologram_system"."mutation" SET "result" = $3
    WHERE "client_id" = $1 AND "seq" = $2
    """

    # Answering a batch that was never claimed is a broken invariant rather than something a
    # caller can be told - the claim and the answer are two halves of one transaction.
    {:ok, %Postgrex.Result{num_rows: 1}} =
      Connection.query(statement, [client_id, seq, result])

    :ok
  end

  @doc """
  Returns what is recorded for the given batch - the user who sent it and the answer it was given -
  or nil when the batch has no record.

  The answer is nil only for a batch being applied at this moment, which cannot be seen from
  outside: the claim lives in the transaction applying it, and that transaction either commits with
  an answer or takes the claim back with it.

  Both halves come back together because a caller needs both: an answer is only ever replayed to
  the session that earned it.
  """
  @spec find(String.t(), non_neg_integer) ::
          %{actor_id: String.t() | nil, result: map | nil} | nil
  def find(client_id, seq) do
    statement = """
    SELECT "actor_id", "result" FROM "hologram_system"."mutation"
    WHERE "client_id" = $1 AND "seq" = $2
    """

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement, [client_id, seq])

    case rows do
      [[actor_id, result]] -> %{actor_id: Codec.decode(actor_id, :uuid), result: result}
      [] -> nil
    end
  end
end
