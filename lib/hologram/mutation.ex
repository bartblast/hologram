defmodule Hologram.Mutation do
  @moduledoc false

  # Applies a batch of client writes: refuses one built against another model, answers one already
  # answered from its record, and runs the rest in ONE transaction under the session's own user.
  #
  # Every write goes through the same executor a server-side verb goes through, so a claim, a
  # value, a reference and a merge are judged exactly as they are for a write made on the server -
  # there is no second set of rules for a write that arrived over the wire. A refusal at any step
  # rolls the whole batch back and names the write it refused - and a refusal the EVALUATOR made
  # is then kept, the batch as it arrived beside its answer, for the session that sent it.

  alias Hologram.Auth
  alias Hologram.Auth.Context
  alias Hologram.Auth.RoleGrant
  alias Hologram.Compiler.Encoder
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
  alias Hologram.Sync.WireData

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

  Returns `{:ok, answer}` - what to send back, spelled as the wire carries it, for a batch that
  landed or one that was refused - or `{:invalid, message}` for a batch that could not be parsed
  at all.

  A batch already answered is answered from its record rather than evaluated a second time, and
  only for the session that sent it.
  """
  @spec run(map, Server.t()) :: {:ok, map} | {:invalid, String.t()}
  def run(raw, server_struct) do
    cond do
      # Checked before anything is parsed: a client built against another model is told exactly
      # that, rather than tripping over a field name its model no longer has.
      not is_binary(raw["model_hash"]) -> {:invalid, "model_hash must be a string"}
      raw["model_hash"] != Model.hash() -> {:ok, rejection(nil, :stale_build)}
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
        raise "batch #{envelope.replica_id}/#{envelope.seq} lost its claim to an arrival that left no answer"

      answer ->
        answer
    end
  end

  # The actor outside, the batch reference inside it, the transaction innermost - the same wrap a
  # command runs under, with the reference added so the outbox knows whose effects these are.
  defp apply_batch(envelope, raw, server_struct) do
    case recorded_answer(envelope, server_struct.user_id) do
      nil -> apply_new_batch(envelope, raw, server_struct)
      answer -> answer
    end
  end

  defp apply_changes(%Write{deltas: deltas}, changes, _index)
       when changes == %{} and deltas == %{},
       do: :ok

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
      :delete -> {run_delete(write, index), nil}
      :drop -> {lost_values(write, stored_columns(row)), stringify(WireData.row(row))}
    end
  end

  defp apply_revocation(write, row) do
    case Merge.resolve_delete(write.based_on, write.stamp, row.__meta__.revisions) do
      :delete ->
        Auth.apply_revocation_write(row, Context.actor_user_id())

        {%{}, nil}

      :drop ->
        {lost_values(write, stored_columns(row)), stringify(WireData.row(row))}
    end
  end

  # ON CONFLICT DO NOTHING holds no lock on the row it conflicted with, and the batch runs at read
  # committed - so a present row is read back LOCKED, which keeps it until the batch commits. A
  # row already gone by then is a revocation committed in between: the grant the write asked for
  # does not exist after all, so the write runs ONCE more and inserts. A second miss cannot be that
  # race twice over; it is a row that conflicts on the fact but does not carry the fact's derived
  # id, which no writer of the store produces - an invariant broken, raised as one rather than
  # retried forever.
  defp apply_grant(write, index, retries_left) do
    grant = Write.to_entity(write)

    case Auth.apply_grant_write(grant, Context.actor_user_id()) do
      :created ->
        {%{}, nil}

      {:error, violations} ->
        Connection.rollback({:rejected, index, violations})

      :present ->
        case EntityOperations.get(RoleGrant, write.id, lock: true) do
          nil when retries_left > 0 ->
            apply_grant(write, index, retries_left - 1)

          nil ->
            raise ArgumentError,
                  "a role grant for this user, resource and role exists under an id that is not " <>
                    "its derivation - every grant row's id is derived from the grant it states"

          row ->
            {lost_values(write, Map.keys(write.data)), stringify(WireData.row(row))}
        end
    end
  end

  defp apply_in_transaction(envelope, server_struct) do
    Connection.transaction(fn ->
      Record.claim!(
        envelope.replica_id,
        envelope.seq,
        server_struct.user_id,
        envelope.model_hash
      )

      result = apply_writes(envelope.writes)

      Record.complete!(envelope.replica_id, envelope.seq, result)

      result
    end)
  end

  defp apply_new_batch(envelope, raw, server_struct) do
    ref = %{replica_id: envelope.replica_id, seq: envelope.seq}

    result =
      Context.with_actor(server_struct.user_id, fn ->
        Ref.with_ref(ref, fn -> apply_in_transaction(envelope, server_struct) end)
      end)

    # A refusal reaches here as the transaction's rollback reason, which is what took the batch's
    # writes, its effects and its claim on the record back with it.
    case result do
      {:ok, answer} ->
        {:ok, answer}

      {:error, :duplicate} ->
        answer_from_race(envelope, server_struct.user_id)

      {:error, {:rejected, index, reason}} ->
        keep_refused(envelope, raw, server_struct.user_id, index, reason)
    end
  end

  # Each clause answers what the write LOST - nothing, or the values a newer edit kept it from
  # setting. A refusal never returns from here: it rolls the whole batch back.
  #
  # A grant is not the writer's to evaluate: it goes to the grant verb's own rules, under the
  # session's actor, and a denial there is the same rejection any denied write answers with. A
  # grant the store already holds is not an error - the verb is idempotent - so the write is
  # confirmed with every column dropped and the stored row as what was kept, read back by the SAME
  # id: the id is derived from the grant, which is what makes the row found the row the write
  # named. Before the generic clause, which would otherwise match.
  defp apply_write(%Write{op: :create, entity_type: RoleGrant} = write, index) do
    apply_grant(write, index, 1)
  end

  defp apply_write(%Write{op: :create} = write, index) do
    result =
      write
      |> Write.to_entity()
      |> Writer.create()

    case result do
      {:ok, _entity} -> {%{}, nil}
      {:error, violations} -> Connection.rollback({:rejected, index, violations})
    end
  end

  # Only the VALUES go through the merge. A delta is not a claim about what the column should
  # hold, so there is nothing to compare it against and nothing for it to lose: it is applied
  # whatever the row's revision is, which is what makes two writers' +1s land as +2.
  defp apply_write(%Write{op: :update} = write, index) do
    row = lock_row(write, index)

    {changes, lost} =
      Merge.resolve(write.data, write.based_on, write.stamp, row.__meta__.revisions)

    apply_changes(write, changes, index)

    {lost_values(write, lost), kept_values(row, lost)}
  end

  # A revocation is judged against the grant as the store holds it, locked for the batch: the
  # verb's own two gates, under the session's actor. It goes through
  # the delete merge first, like any delete - a grant can be deleted and re-made under one id,
  # so a revocation based on an earlier grant's revisions loses to a newer one and answers the
  # way any stale delete does. A row already gone is what the verb itself answers: nothing.
  defp apply_write(%Write{op: :delete, entity_type: RoleGrant} = write, _index) do
    # The gate runs before the lookup, asked about the grant the write states rather than about
    # the row: a grant's id is derived from its grant, so a delete of any grant is something every
    # client can send, and whether the row is there is an answer for whoever may revoke it. Asked
    # this way, an actor who may not gets the same refusal either way, and a stale revocation's
    # answer - the row it was stale against - stays behind the same gate.
    grant = Write.to_entity(write)
    Auth.authorize_revocation_write!(grant, Context.actor_user_id())

    case EntityOperations.get(RoleGrant, write.id, lock: true) do
      nil -> {%{}, nil}
      row -> apply_revocation(write, row)
    end
  end

  defp apply_write(%Write{op: :delete} = write, index) do
    case EntityOperations.get(write.entity_type, write.id, lock: true) do
      # Deleting a row that is not there is what the verb itself does: nothing, and no complaint.
      nil -> {%{}, nil}
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
      :ok -> {%{}, nil}
      {:error, violations} -> Connection.rollback({:rejected, index, violations})
    end
  end

  defp apply_writes(writes) do
    verdicts =
      writes
      |> Enum.with_index()
      |> Enum.reduce(%{dropped: %{}, kept: %{}}, &collect_verdicts/2)

    %{"status" => "confirmed", "dropped" => verdicts.dropped, "kept" => verdicts.kept}
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

  # What each write LOST and what the row KEPT in its place, both keyed by the write's position.
  #
  # The index is a string because the answer is stored as jsonb and sent as JSON, where an object's
  # keys are strings whatever they started as.
  defp collect_verdicts({write, index}, verdicts) do
    {lost, kept} = apply_write(write, index)
    key = Integer.to_string(index)

    verdicts
    |> put_verdict(:dropped, key, lost)
    |> put_verdict(:kept, key, kept)
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

  # A refusal took the batch back - its writes, its effects and its claim on the record - so what
  # is kept of it is written after the rollback, on its own statement: the batch as it arrived and
  # the answer it got, so that a change a browser made and then lost is somewhere, with the reason.
  #
  # Only a refusal the EVALUATOR made reaches here. A batch refused before its transaction was
  # refused for its build or its clock rather than for what it writes, and the server read nothing
  # of it worth keeping - a stale one it could not parse at all.
  #
  # Nothing is kept for an anonymous session either: an answer is replayed only to the session that
  # earned it, and one anonymous session cannot be told from another - so a refusal kept under no
  # actor would be readable by a stranger, or by nobody.
  # What the row KEPT where this write lost, spelled the way a frame spells a patch - the winning
  # values and the revisions they carry.
  #
  # Sent because the answer can reach the client BEFORE the frame carrying those values does, and
  # a client that knows only which of its own values lost has nothing to put in their place but
  # the value the row held before either writer touched it. Naming the winner is what lets it move
  # straight from what it wrote to what stands, with nothing in between.
  #
  # Server-only columns cannot appear here: a client cannot write one, so none can lose - and
  # WireData would drop it in any case.
  defp kept_values(_row, []), do: nil

  defp kept_values(%entity_type{} = row, names) do
    values =
      row
      |> Map.from_struct()
      |> Map.take(names)

    revisions = Map.take(row.__meta__.revisions, names)

    entity_type
    |> WireData.patch(values)
    |> Map.put(:"$revisions", revisions)
    |> stringify()
  end

  defp keep_refused(envelope, raw, actor_id, index, reason) do
    answer = rejection(index, reason)

    if actor_id do
      Record.refuse!(
        envelope.replica_id,
        envelope.seq,
        actor_id,
        envelope.model_hash,
        raw,
        answer
      )
    end

    {:ok, answer}
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

  # An answer is replayed only to the session that earned it. Anyone can present anyone's replica id
  # and sequence number, and a stored answer is revealing - a denial names a row, a violation map
  # shows what was written - so a record belonging to another session is refused rather than read
  # back. An anonymous session's record has no actor and matches only another anonymous one, which
  # is the same rule rather than an exception to it.
  defp parse_and_apply(raw, server_struct) do
    with {:ok, envelope} <- parse(raw),
         :ok <- check_clocks(envelope.writes) do
      apply_batch(envelope, raw, server_struct)
    else
      {:invalid, message} -> {:invalid, message}
      {:rejected, index, reason} -> {:ok, rejection(index, reason)}
    end
  end

  # A write that lost nothing and a row that kept nothing are both spoken of by saying nothing -
  # an entry per write would make every answer carry a key for each of them.
  defp put_verdict(verdicts, _kind, _key, nil), do: verdicts

  defp put_verdict(verdicts, _kind, _key, values) when values == %{}, do: verdicts

  defp put_verdict(verdicts, kind, key, values) do
    Map.update!(verdicts, kind, &Map.put(&1, key, values))
  end

  defp recorded_answer(envelope, actor_id) do
    case Record.find(envelope.replica_id, envelope.seq) do
      nil -> nil
      %{actor_id: ^actor_id, result: nil} -> nil
      %{actor_id: ^actor_id, result: result} -> {:ok, result}
      _another_sessions -> {:ok, rejection(nil, :forged_client)}
    end
  end

  # The answer a refusal travels as: the position of the write it names - nil for a refusal of the
  # whole batch - and the reason as an encoded client term, since a reason is an arbitrary term (a
  # field-keyed map holding a regex or a range, an exception struct) that JSON cannot spell and the
  # client's interpreter already reads. Built here and nowhere else, so that what the record stores
  # is byte for byte what the wire carried.
  @spec rejection(non_neg_integer | nil, rejection) :: map
  defp rejection(index, reason) do
    %{
      "reason" => Encoder.encode_client_term!(reason),
      "status" => "rejected",
      "write" => index
    }
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

  # The answer travels as JSON and is stored as jsonb, where every key is a string - so it is
  # spelled that way here, and the map a caller reads is the map a client reads whichever side it
  # was built on.
  defp stringify(data), do: Map.new(data, &stringify_entry/1)

  defp stringify_entry({:"$revisions", revisions}), do: {"$revisions", stringify(revisions)}

  defp stringify_entry({name, value}), do: {Atom.to_string(name), value}
end
