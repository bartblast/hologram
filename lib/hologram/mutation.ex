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
  alias Hologram.DB.Clock
  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.EntityOperations
  alias Hologram.DB.Merge
  alias Hologram.DB.Writer
  alias Hologram.Entity.Model
  alias Hologram.Mutation.Envelope
  alias Hologram.Mutation.Record
  alias Hologram.Mutation.Ref
  alias Hologram.Mutation.Write
  alias Hologram.Server

  # How far ahead of this node's wall clock a writer's stamp may run. A stamp is stored as given -
  # rewriting it would break the chain its writer's next write is based on - so a clock set far
  # into the future is refused rather than corrected, and one within the allowance can win an
  # unfair tiebreak for at most this long. The number is policy: its floor is real (a synchronized
  # device is within milliseconds, an unsynchronized one drifts seconds to minutes, so under a
  # minute would refuse honest clients), its ceiling is judgement, and five minutes is where
  # Kerberos put its skew tolerance for the same reason. Overridable per app under the :mutation
  # key, since a managed fleet can afford a tighter one.
  @default_clock_allowance_ms 300_000

  @type rejection ::
          :stale_build
          | :clock
          | :forged_client
          | :not_found
          | %Hologram.AccessDeniedError{}
          | map

  @doc """
  Applies the given batch, as the request decoded it, on behalf of the given session.

  Returns what to answer: the result of a batch that landed, the write and the reason of one that
  was refused, or the message of one that could not be parsed at all.

  A batch already applied is answered from its record rather than applied a second time, and only
  for the session that sent it.
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

  defp allowance_ms do
    :hologram
    |> Application.get_env(:mutation, [])
    |> Keyword.get(:clock_allowance_ms, @default_clock_allowance_ms)
  end

  # The claim lost to an arrival that has COMMITTED by now: a unique violation against a row still
  # uncommitted blocks until that transaction ends, and one that ends by aborting leaves the key
  # free - so the only way to lose the key is to lose it to a batch that finished, answer and all.
  defp answer_from_race(envelope, actor_id) do
    case recorded_answer(envelope, actor_id) do
      nil ->
        raise "batch #{envelope.client_id}/#{envelope.seq} lost its claim to an arrival that left no answer"

      answer ->
        answer
    end
  end

  # The actor outside, the batch reference inside it, the transaction innermost - the same wrap a
  # command runs under, with the reference added so the outbox knows whose effects these are.
  defp apply_batch(envelope, server_struct) do
    case recorded_answer(envelope, server_struct.user_id) do
      nil -> apply_new_batch(envelope, server_struct)
      answer -> answer
    end
  end

  defp apply_changes(_write, changes, _index) when changes == %{}, do: :ok

  defp apply_changes(write, changes, index) do
    result =
      %{write | data: changes}
      |> Write.to_entity()
      |> Writer.update()

    case result do
      :ok -> :ok
      {:error, violations} -> Connection.rollback({:rejected, index, violations})
    end
  end

  defp apply_delete(write, row, index) do
    case Merge.resolve_delete(write.based_on, write.stamp, row.__meta__.revisions) do
      :delete -> run_delete(write, index)
      :drop -> lost_values(write, stored_columns(row))
    end
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

  defp apply_new_batch(envelope, server_struct) do
    ref = %{client_id: envelope.client_id, seq: envelope.seq}

    result =
      Context.with_actor(server_struct.user_id, fn ->
        Ref.with_ref(ref, fn -> apply_in_transaction(envelope, server_struct) end)
      end)

    # A refusal reaches here as the transaction's rollback reason, which is what took the batch's
    # writes, its effects and its claim on the record back with it.
    case result do
      {:ok, answer} -> {:ok, answer}
      {:error, :duplicate} -> answer_from_race(envelope, server_struct.user_id)
      {:error, {:rejected, index, reason}} -> {:rejected, index, reason}
    end
  end

  # Each clause answers what the write LOST - nothing, or the values a newer edit kept it from
  # setting. A refusal never returns from here: it rolls the whole batch back.
  defp apply_write(%Write{op: :create} = write, index) do
    result =
      write
      |> Write.to_entity()
      |> Writer.create()

    case result do
      {:ok, _entity} -> %{}
      {:error, violations} -> Connection.rollback({:rejected, index, violations})
    end
  end

  defp apply_write(%Write{op: :update} = write, index) do
    row = lock_row(write, index)

    {changes, lost} =
      Merge.resolve(write.data, write.based_on, write.stamp, row.__meta__.revisions)

    apply_changes(write, changes, index)

    lost_values(write, lost)
  end

  defp apply_write(%Write{op: :delete} = write, index) do
    case EntityOperations.get(write.entity_type, write.id, lock: true) do
      # Deleting a row that is not there is what the verb itself does: nothing, and no complaint.
      nil -> %{}
      row -> apply_delete(write, row, index)
    end
  end

  defp apply_write(%Write{op: op} = write, index)
       when op in [:add_relationship, :delete_relationship] do
    lock_row(write, index)

    result =
      write
      |> Write.to_entity()
      |> Writer.update()

    case result do
      :ok -> %{}
      {:error, violations} -> Connection.rollback({:rejected, index, violations})
    end
  end

  defp apply_writes(writes) do
    dropped =
      writes
      |> Enum.with_index()
      |> Enum.reduce(%{}, &collect_lost/2)

    %{"status" => "confirmed", "dropped" => dropped}
  end

  # Checked before anything runs, against the writes as a whole - a stamp the server cannot vouch
  # for refuses the batch and names the write that carried it.
  defp check_clocks(writes) do
    writes
    |> Enum.with_index()
    |> Enum.find_value(:ok, fn {write, index} ->
      if clock_off?(write), do: {:rejected, index, :clock}
    end)
  end

  # Two ways a stamp is one this node cannot vouch for. Its wall clock runs further ahead of this
  # node's than the allowance, which is a device with the wrong time. Or it is not above a revision
  # the same write says it was based on - a writer's stamp is above everything it has seen, so this
  # is a clock that went backwards, and the executor would raise the stamp to the stored revision
  # plus one on the way in, which is the one rewrite the design forbids.
  defp clock_off?(%Write{stamp: nil}), do: false

  defp clock_off?(%Write{stamp: stamp, based_on: based_on}) do
    Clock.wall_clock_ms(stamp) > System.os_time(:millisecond) + allowance_ms() or
      Enum.any?(based_on, fn {_name, revision} -> stamp <= revision end)
  end

  # The index is a string because the answer is stored as jsonb and sent as JSON, where an object's
  # keys are strings whatever they started as.
  defp collect_lost({write, index}, dropped) do
    case apply_write(write, index) do
      lost when lost == %{} -> dropped
      lost -> Map.put(dropped, Integer.to_string(index), lost)
    end
  rescue
    # A denial is the one refusal the executor RAISES rather than returns, because on the server it
    # is a programming error to write what the acting user may not. Here it is an ordinary answer:
    # a client asking for something it may not have is the system working. Anything else raised
    # propagates - the transaction rolls back and re-raises it, which is what a bug should do.
    error in Hologram.AccessDeniedError -> Connection.rollback({:rejected, index, error})
  end

  # Asked only about fields an envelope already admitted, so unlike the parser's own map this one
  # needs no server-only filter - it answers what type a field holds, for every field there is.
  defp field_types(entity_type) do
    attributes = Map.new(entity_type.__attributes__(), fn {name, type, _opts} -> {name, type} end)

    references =
      entity_type.__relationships__()
      |> Enum.reject(fn {_name, type, _opts} -> is_list(type) end)
      |> Map.new(fn {name, _type, _opts} -> {String.to_existing_atom("#{name}_id"), :uuid} end)

    Map.merge(attributes, references)
  end

  defp lock_row(write, index) do
    case EntityOperations.get(write.entity_type, write.id, lock: true) do
      nil -> Connection.rollback({:rejected, index, :not_found})
      row -> row
    end
  end

  # What the write tried to set and did not, spelled as the client sent it. This is the only place
  # a losing value survives: it never reached the row, so it is in no log, and a batch that was
  # CONFIRMED keeps no envelope. A dropped delete carries no values, so its columns answer nothing.
  defp lost_values(_write, []), do: %{}

  defp lost_values(write, names) do
    types = field_types(write.entity_type)

    Map.new(names, fn name ->
      {Atom.to_string(name), Codec.encode_json(Map.get(write.data, name), types[name])}
    end)
  end

  defp parse(raw) do
    case Envelope.parse(raw) do
      {:ok, envelope} -> {:ok, envelope}
      {:error, message} -> {:invalid, message}
    end
  end

  # An answer is replayed only to the session that earned it. Anyone can present anyone's client id
  # and sequence number, and a stored answer is revealing - a denial names a row, a violation map
  # shows what was written - so a record belonging to another session is refused rather than read
  # back. An anonymous session's record has no actor and matches only another anonymous one, which
  # is the same rule rather than an exception to it.
  defp parse_and_apply(raw, server_struct) do
    with {:ok, envelope} <- parse(raw),
         :ok <- check_clocks(envelope.writes) do
      apply_batch(envelope, server_struct)
    end
  end

  defp recorded_answer(envelope, actor_id) do
    case Record.find(envelope.client_id, envelope.seq) do
      nil -> nil
      %{actor_id: ^actor_id, result: nil} -> nil
      %{actor_id: ^actor_id, result: result} -> {:ok, result}
      _another_sessions -> {:rejected, nil, :forged_client}
    end
  end

  defp run_delete(write, index) do
    result =
      write
      |> Write.to_entity()
      |> Writer.delete()

    case result do
      :ok -> %{}
      {:error, reason} -> Connection.rollback({:rejected, index, reason})
    end
  end

  # Every column the row holds a revision of, which is every column a delete would have taken.
  defp stored_columns(row) do
    row.__meta__.revisions
    |> Map.keys()
    |> Enum.sort()
  end
end
