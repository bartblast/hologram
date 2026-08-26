defmodule Hologram.Mutation.Record do
  @moduledoc false

  # One row per batch of client writes the server ANSWERED, keyed by the replica that sent it and
  # that replica's own sequence number - the primary key IS the dedup.
  #
  # A batch that LANDS is claimed first, inside its own transaction and with no answer yet, so a
  # second arrival of the same batch blocks on the key until the first commits and then fails its
  # own claim, and the answer is written just before the commit. A claim with no answer therefore
  # cannot be observed from outside: it exists only inside the transaction holding it, which
  # either commits with an answer or takes the claim with it.
  #
  # A batch the evaluator REFUSED is written afterwards instead, on its own statement - its claim
  # rolled back with everything else the transaction did - and it keeps the batch as it arrived
  # beside the answer, since its rows reached no log and exist nowhere else on the server.
  #
  # A landed batch's envelope is not kept: the rows it wrote are in the effect log under
  # mutation_ref, keyed by the same pair, so keeping it here would keep every write twice.

  alias Hologram.DB.Codec
  alias Hologram.DB.Connection

  @doc """
  Claims the record for the given batch in the caller's transaction and returns :ok.

  Rolls the transaction back with :duplicate when the batch is already recorded - by an earlier
  arrival, or by a concurrent one that committed while this transaction was running. Such a batch
  is answered from its record rather than applied again.
  """
  @spec claim!(String.t(), non_neg_integer, String.t() | nil, String.t()) :: :ok
  def claim!(replica_id, seq, actor_id, model_hash) do
    statement = """
    INSERT INTO "hologram_system"."mutation" ("replica_id", "seq", "actor_id", "model_hash")
    VALUES ($1, $2, $3, $4)
    """

    params = [replica_id, seq, Codec.encode(actor_id, :uuid), model_hash]

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
  def complete!(replica_id, seq, result) do
    statement = """
    UPDATE "hologram_system"."mutation" SET "result" = $3
    WHERE "replica_id" = $1 AND "seq" = $2
    """

    # Answering a batch that was never claimed is a broken invariant rather than something a
    # caller can be told - the claim and the answer are two halves of one transaction.
    {:ok, %Postgrex.Result{num_rows: 1}} =
      Connection.query(statement, [replica_id, seq, result])

    :ok
  end

  @doc """
  Returns what is recorded for the given batch - the user who sent it and the answer it was given,
  a confirmation or a refusal - or nil when the batch has no record.

  The answer is nil only for a batch being applied at this moment, which cannot be seen from
  outside: the claim lives in the transaction applying it, and that transaction either commits with
  an answer or takes the claim back with it.

  Both halves come back together because a caller needs both: an answer is only ever replayed to
  the session that earned it.
  """
  @spec find(String.t(), non_neg_integer) ::
          %{actor_id: String.t() | nil, result: map | nil} | nil
  def find(replica_id, seq) do
    statement = """
    SELECT "actor_id", "result" FROM "hologram_system"."mutation"
    WHERE "replica_id" = $1 AND "seq" = $2
    """

    {:ok, %Postgrex.Result{rows: rows}} = Connection.query(statement, [replica_id, seq])

    case rows do
      [[actor_id, result]] -> %{actor_id: Codec.decode(actor_id, :uuid), result: result}
      [] -> nil
    end
  end

  @doc """
  Records the given batch as refused - the batch as it arrived and the answer it got, bound to the
  user who sent it - and returns :ok.

  A batch already recorded is left as it is, so two arrivals of one refused batch do not collide.
  """
  @spec refuse!(String.t(), non_neg_integer, String.t(), String.t(), map, map) :: :ok
  def refuse!(replica_id, seq, actor_id, model_hash, envelope, answer) do
    # Outside any transaction by intent: the refusal already took the batch's transaction back,
    # and this is the one statement that outlives it.
    statement = """
    INSERT INTO "hologram_system"."mutation"
      ("replica_id", "seq", "actor_id", "model_hash", "envelope", "result")
    VALUES ($1, $2, $3, $4, $5, $6)
    ON CONFLICT ("replica_id", "seq") DO NOTHING
    """

    params = [replica_id, seq, Codec.encode(actor_id, :uuid), model_hash, envelope, answer]

    {:ok, _result} = Connection.query(statement, params)

    :ok
  end
end
