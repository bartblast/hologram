defmodule Hologram.Mutation do
  @moduledoc false

  # Applies a batch of client writes: refuses one built against another model, answers one already
  # applied from its record, and runs the rest in ONE transaction under the session's own user.
  #
  # Every write goes through the same executor a server-side verb goes through, so a claim, a
  # value, a reference and a merge are judged exactly as they are for a write made on the server -
  # there is no second set of rules for a write that arrived over the wire. A refusal at any step
  # rolls the whole batch back and names the write it refused.

  alias Hologram.Auth.Context
  alias Hologram.DB.Connection
  alias Hologram.DB.Writer
  alias Hologram.Entity.Model
  alias Hologram.Mutation.Envelope
  alias Hologram.Mutation.Record
  alias Hologram.Mutation.Ref
  alias Hologram.Mutation.Write
  alias Hologram.Server

  @type rejection :: :stale_build | :clock | :not_found | %Hologram.AccessDeniedError{} | map

  @doc """
  Applies the given batch, as the request decoded it, on behalf of the given session.

  Returns what to answer: the result of a batch that landed, the write and the reason of one that
  was refused, or the message of one that could not be parsed at all.
  """
  @spec run(map, Server.t()) ::
          {:ok, map} | {:rejected, non_neg_integer | nil, rejection} | {:invalid, String.t()}
  def run(raw, server_struct) do
    cond do
      # Checked before anything is parsed: a client built against another model is told exactly
      # that, rather than tripping over a field name its model no longer has.
      not is_binary(raw["model_hash"]) -> {:invalid, "model_hash must be a string"}
      raw["model_hash"] != Model.hash() -> {:rejected, nil, :stale_build}
      true -> parse_and_apply(raw, server_struct)
    end
  end

  # The actor outside, the batch reference inside it, the transaction innermost - the same wrap a
  # command runs under, with the reference added so the outbox knows whose effects these are.
  defp apply_batch(envelope, server_struct) do
    ref = %{client_id: envelope.client_id, seq: envelope.seq}

    Context.with_actor(server_struct.user_id, fn ->
      Ref.with_ref(ref, fn -> apply_in_transaction(envelope, server_struct) end)
    end)
  end

  defp apply_in_transaction(envelope, server_struct) do
    Connection.transaction(fn ->
      Record.claim!(
        envelope.client_id,
        envelope.seq,
        server_struct.user_id,
        envelope.model_hash
      )

      result = apply_writes(envelope.writes)

      Record.complete!(envelope.client_id, envelope.seq, result)

      result
    end)
  end

  defp apply_write(%Write{op: :create} = write, index) do
    result =
      write
      |> Write.to_entity()
      |> Writer.create()

    case result do
      {:ok, _entity} -> :ok
      {:error, violations} -> Connection.rollback({:rejected, index, violations})
    end
  end

  defp apply_writes(writes) do
    writes
    |> Enum.with_index()
    |> Enum.each(fn {write, index} -> apply_write(write, index) end)

    %{"status" => "confirmed", "dropped" => %{}}
  end

  defp parse_and_apply(raw, server_struct) do
    case Envelope.parse(raw) do
      {:ok, envelope} -> apply_batch(envelope, server_struct)
      {:error, message} -> {:invalid, message}
    end
  end
end
