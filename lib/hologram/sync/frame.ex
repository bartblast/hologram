defmodule Hologram.Sync.Frame do
  @moduledoc false

  # What a client is sent, on the stream it already has open. Deltas ride beside the realtime
  # events as their own chunk kinds rather than on a connection of their own, so a tab keeps one
  # stream and sync inherits its handshake, heartbeats and reconnect.
  #
  # These five kinds carry JSON where every other chunk on that stream carries JavaScript source.
  # The others hand over arbitrary terms and need an encoder that can spell any of them - a delta
  # holds values a database stores, and paying ten times the bytes to say so, on the payload a
  # whole-app fill is mostly made of, buys nothing.

  alias Hologram.Auth
  alias Hologram.DB.Codec
  alias Hologram.DB.QueryCache
  alias Hologram.Entity.Model
  alias Hologram.Policy
  alias Hologram.Sync.WireData

  @protocol_version 1

  @doc """
  Turns what a session worked out for one client into the deltas a frame carries.

  A row that appeared travels whole, because a client that did not have it needs all of it, with
  the server's verdicts for the given user (see `put_entity/2`): the ones given for it, per entity
  type and id - worked out already, as a batch's recheck works them out - and otherwise worked out
  here (see `row_verdicts/2`). A row that changed travels as the attributes that moved, each patch
  given as `{row, changes, verdicts}` - the verdicts that moved beside them, or nil when none did.
  A row that left travels as its id, and an edge as the pair it joined or parted.

  Every delta names its own type: an arrived row carries it, an edge carries the type of the row
  the relationship lives on, and a row that left arrives here as its id paired with the type it
  was held under - a row no longer there to be asked is named by the bookkeeping that watched it
  arrive.

  News may also hold `hidden`, the rows a client may hold that no longer reach it, as
  `{entity_type, salt, ids}` - told by hash rather than by id (see `unsync_hashed/3`).
  """
  @spec deltas(map, Hologram.Server.identity_id() | nil, %{module => %{String.t() => map}}) ::
          list(map)
  def deltas(news, actor_user_id, verdicts \\ %{}) do
    Enum.concat([
      Enum.map(news.appeared, &put_entity(&1, appeared_verdicts(&1, actor_user_id, verdicts))),
      Enum.map(news.patched, fn {row, patch, verdicts} -> patch_entity(row, patch, verdicts) end),
      Enum.map(news.unsynced, fn {id, entity_type} -> unsync_entity(id, entity_type) end),
      Enum.map(Map.get(news, :hidden, []), fn {entity_type, salt, ids} ->
        unsync_hashed(entity_type, salt, ids)
      end),
      Enum.map(news.edges, &relationship/1)
    ])
  end

  @doc """
  Returns the hash a client is told to drop a row by (see `unsync_hashed/3`): the first 64 bits of
  the SHA-256 of the given salt followed by the row's id, as 16 lowercase hex digits. The browser
  works the same hash out over the ids it holds (`assets/js/drop_hash.mjs`).

  It has to keep the id from being read back, which holds for an id with random bits in it - not
  for one worked out from what it names, like a grant's, which is never dropped by hash, only kept
  by it (see `keep_hashed/3`). An id `Hologram.Entity.generate_id/0` makes is a UUIDv7: a creation
  time to the millisecond and 74 random bits. Finding ids that hash to a given one means trying the random
  bits one guess at a time - there is no shortcut back through SHA-256 - and even a search that
  could finish would leave a thousand ids per hash for every millisecond the row may have been
  created in, 74 bits against 64, with nothing to tell the dropped one apart. Telling one apart
  takes knowing it already.
  """
  @spec drop_hash(String.t(), String.t()) :: String.t()
  def drop_hash(salt, id) do
    <<prefix::binary-size(8), _rest::binary>> = :crypto.hash(:sha256, salt <> id)

    Base.encode16(prefix, case: :lower)
  end

  @doc """
  Returns a fresh salt for hashing the ids of the rows a client is told to drop: 16 random bytes,
  url-safe base64 without padding. One per catch-up, so the same row is told under another hash
  each time, and two clients' drops can't be laid side by side.
  """
  @spec drop_salt() :: String.t()
  def drop_salt do
    16
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Builds the SSE event-stream chunk carrying a batch of deltas, with the place in the log they
  leave the client at.

  The cursor is the client's to keep and hand back, never to read: what it is made of is the
  reader's business, so its shape can change without the protocol changing.

  The model hash is stamped once for the frame rather than once per delta. Every value in it was
  read from the rows as they stand, so a frame's deltas are always of one model - a delta carrying
  values written under an older one is a thing only stored values could produce, and none are
  sent.

  The deltas travel grouped op -> type, with the payload alone as the delta: a whole row for a
  put (its id is one of its attributes), the changed attributes plus the id for a patch or an
  edge, and the bare id for an unsync. The op and type are spelled once per group rather than
  once per delta - constants amortize to nothing on the payload an app-wide fill is mostly made
  of. Grouping loses no ordering, because a frame's deltas are statements about one snapshot. A
  row and an edge of its own can both be in one, and often are - a row that arrives with a pair
  added in the same round is the ordinary case - but they cannot disagree: the row states the
  whole target set of what the window embeds, the edge states one pair of it, and both were read
  from the one round. Whichever is applied first, the same facts are left behind.

  The applied sequence number says how far the receiving replica's own writes are reflected in
  what this frame carries: every batch it sent up to that number has been applied to the rows the
  frame was built from. That is what lets it tell a change of its own, arriving back, from one it
  has still to make - which the values cannot say, since a write that landed looks exactly like
  the write that made it.

  It is ONE integer, and it is about the receiving replica alone - never a list of who wrote what.
  A frame therefore says nothing about any other replica's writes, which is the whole of what
  keeps this from telling one client which rows another client is responsible for.

  Nil says nothing rather than nothing-applied: a stream serving no replica has no number to give,
  and a reader must not read that as "none of my writes have landed".
  """
  @spec encode_deltas_envelope(integer, String.t() | nil, list(map), non_neg_integer | nil) ::
          String.t()
  def encode_deltas_envelope(id, cursor, deltas, applied_seq) do
    payload = %{
      applied_seq: applied_seq,
      cursor: cursor,
      deltas: group(deltas),
      model_hash: Model.hash(),
      protocol_version: @protocol_version
    }

    "event: sync_deltas\nid: #{id}\ndata: #{Jason.encode!(payload)}\n\n"
  end

  @doc """
  Builds the SSE event-stream chunk saying how much of what the client will hold has arrived.

  The scope says which queries it may now answer from its own store: `{:types, types}` names entity
  types whose every row the client may see it now holds, and `:all` says it holds everything, so
  navigating needs no server. Until a query's types have arrived the client answers it from what
  the server rendered, because a store filled only part way would answer with part of the truth.

  Per entity type rather than per page or per window, because a type is what a fill sends whole,
  and whether it is complete is the same claim on every page and in every tab - which a page is
  not. The types are spelled the way a frame spells a row's type.

  The place comes with the marker for the same reason the marker exists: this is the moment the
  client holds a whole pot, and a place is a claim only a client holding one can honour. A deltas
  frame carries it too, but a client filled and then left alone receives no further frame - so
  without this a quiet app would keep everything it was sent and still have nowhere to resume
  from, and would be filled from nothing on its next visit.

  Whether the marker names a place is about the CLIENT, not the scope. A first arrival holds a
  whole pot only once `:all` has been announced, so its types markers name none - the scope is
  narrower than the claim. And nil for `:all` on a build whose windows have no places to speak of.
  """
  @spec encode_synced_envelope(integer, :all | {:types, list(module)}, String.t() | nil) ::
          String.t()
  def encode_synced_envelope(id, scope, cursor) do
    payload =
      scope
      |> scope_payload()
      |> Map.merge(%{cursor: cursor, protocol_version: @protocol_version})

    "event: synced\nid: #{id}\ndata: #{Jason.encode!(payload)}\n\n"
  end

  @doc """
  Builds the SSE event-stream chunk telling a client to drop everything it holds, because what
  follows is the whole of what it may see rather than what changed.

  Sent when a returning client cannot be told what it missed - its place could not be read, it was
  judged under rules other than the current ones, the place predates the log, the gap is too big to
  be worth replaying, or the gap spans a change of model. The reason says which, for the sake of
  whoever is looking at why a client paid for a resync, and the client does the same thing
  whichever it is.

  It is its own chunk rather than a flag on the rows that follow, because there may be none: a
  client whose rows are all gone still has to be told to let go of them.
  """
  @spec encode_resync_envelope(integer, atom) :: String.t()
  def encode_resync_envelope(id, reason) do
    payload = %{protocol_version: @protocol_version, reason: reason}

    "event: sync_resync\nid: #{id}\ndata: #{Jason.encode!(payload)}\n\n"
  end

  @doc """
  Builds the SSE event-stream chunk telling a client its bundle no longer matches this build.

  It is a notice rather than an order, and what the client makes of it is the client's business:
  it is told that nothing will be synced to it, not told to restart. A client that threw its page
  away over this would be throwing away what someone was doing to fix a mismatch they did not
  cause - and the direction of travel is the other way, towards serving a client of an older
  model through adapter chains rather than asking it to catch up.
  """
  @spec encode_reload_envelope(integer, atom) :: String.t()
  def encode_reload_envelope(id, reason) do
    payload = %{protocol_version: @protocol_version, reason: reason}

    "event: sync_reload\nid: #{id}\ndata: #{Jason.encode!(payload)}\n\n"
  end

  @doc """
  Builds the SSE event-stream chunk handing a client the rules this build enforces, rendered (see
  `Hologram.Compiler.render_rules/1`), with the hash they go by.

  Sent to a client whose bundle was built with other rules but the same model - a deploy that
  changed only policies - so it answers permission checks the way the server does from its next
  render, without reloading. The hash is what the client greets with from then on, so a reconnect
  is not sent them again. The rules are spliced in as rendered rather than encoded again: they are
  JSON already, cached once for every client a deploy sends back.
  """
  @spec encode_rules_envelope(integer, String.t(), String.t()) :: String.t()
  def encode_rules_envelope(id, policy_hash, rules) do
    payload = %{
      policy_hash: policy_hash,
      protocol_version: @protocol_version,
      rules: Jason.Fragment.new(rules)
    }

    "event: sync_rules\nid: #{id}\ndata: #{Jason.encode!(payload)}\n\n"
  end

  @doc """
  Returns the protocol version this build speaks.
  """
  @spec protocol_version() :: pos_integer
  def protocol_version, do: @protocol_version

  @doc """
  Returns the delta handing a client a whole row, which is what a client that does not have it
  needs, with the server's verdicts on the operations of the row's type for the client's user (see
  `row_verdicts/2`).

  The verdicts travel beside the row's data as `$verdicts`, a name no attribute can have, the way
  its revisions travel as `$revisions` - and only when there are some, so a row of a type the
  server sends no verdict on is spelled as it always was.
  """
  @spec put_entity(struct, %{String.t() => boolean}) :: map
  def put_entity(row, verdicts) do
    row_data = WireData.row(row)
    data = if verdicts == %{}, do: row_data, else: Map.put(row_data, :"$verdicts", verdicts)

    %{data: data, id: row.id, op: :put_entity, type: type_of(row)}
  end

  @doc """
  Returns the server's verdicts on the operations of the given row's type for the given user, as a
  put carries them (see `Hologram.Auth.verdicts/2`) - none when the build has no client checking
  permissions, which never reads one, or the server sends no verdict on the row's type (see
  `Hologram.Policy.verdict_operations/1`).
  """
  @spec row_verdicts(Hologram.Server.identity_id() | nil, struct) :: %{String.t() => boolean}
  def row_verdicts(actor_user_id, %entity_type{} = row) do
    if Policy.verdict_operations(entity_type) != [] and QueryCache.permission_checking?() do
      Auth.verdicts(actor_user_id, row)
    else
      %{}
    end
  end

  @doc """
  Returns the delta telling a client a row is no longer its to hold.

  Not the same as the row being gone: this says the client may no longer see it, which is why the
  type comes from the caller - a row that left is no longer there to name its own.
  """
  @spec unsync_entity(String.t(), module) :: map
  def unsync_entity(id, entity_type) do
    %{id: id, op: :unsync_entity, type: Codec.encode_enum_value(entity_type)}
  end

  @doc """
  Returns the delta telling a client to keep only the given rows of the given entity type, each
  named by its hash under the given salt (see `drop_hash/2`), and to drop every other row of the
  type it holds.

  For a returning client whose user lost a grant reaching every row of a type: the rows the grant
  hid can't be listed without reading the whole type, while the rows the user may still read are
  what the session reads anyway. And for the grants a returning client may hold that its user can
  no longer read: a grant's id is worked out from what it names, so dropping one by hash would let
  a client confirm a grant it guessed, while a list of the grants it may keep names only grants it
  may read. Named by hash for the same reason a drop is, and whole - a client keeping only part of
  the list would drop the rest.
  """
  @spec keep_hashed(module, String.t(), list(String.t())) :: map
  def keep_hashed(entity_type, salt, ids) do
    %{
      data: %{hashes: Enum.map(ids, &drop_hash(salt, &1)), salt: salt},
      op: :keep_hashed,
      type: Codec.encode_enum_value(entity_type)
    }
  end

  @doc """
  Returns the delta telling a client to drop whichever of the given rows of the given entity type
  it holds, each named by its hash under the given salt rather than by its id (see `drop_hash/2`).

  For rows a client may hold that the session can't say it does: their user lost them before the
  session read what a returning client holds. Telling a client the ids of rows it never had would
  tell it rows exist that it may not read, while a hash names a row only to a client that has it.
  """
  @spec unsync_hashed(module, String.t(), list(String.t())) :: map
  def unsync_hashed(entity_type, salt, ids) do
    %{
      data: %{hashes: Enum.map(ids, &drop_hash(salt, &1)), salt: salt},
      op: :unsync_hashed,
      type: Codec.encode_enum_value(entity_type)
    }
  end

  defp appeared_verdicts(%entity_type{id: id} = row, actor_user_id, verdicts) do
    case verdicts do
      %{^entity_type => %{^id => row_verdicts}} -> row_verdicts
      _not_given -> row_verdicts(actor_user_id, row)
    end
  end

  defp group(deltas) do
    deltas
    |> Enum.group_by(& &1.op)
    |> Map.new(fn {op, grouped} -> {op, group_by_type(op, grouped)} end)
  end

  defp group_by_type(op, deltas) do
    deltas
    |> Enum.group_by(& &1.type)
    |> Map.new(fn {type, grouped} -> {type, Enum.map(grouped, &payload(op, &1))} end)
  end

  # The row comes along for its type as much as its id: a bag of changed attributes cannot say
  # what it belongs to, and without that the values cannot be written the way the wire wants them.
  #
  # Every column the patch names was set at a revision the row's own map holds - the row is the
  # fresh read the frame is built from - so the patch carries those entries and the client writes
  # them over its map rather than being sent one. They are taken against the WRITTEN data rather
  # than against the changes: a change to a server-only column reaches here (the log stopped
  # dropping it) and is gone from the data, so taking from the data is what keeps a client from
  # being told that a column it may not have has moved.
  #
  # Verdicts that moved ride the patch as `$verdicts`, replacing what the client holds - nil when
  # they did not move, which leaves them out. A row whose verdicts moved while none of its values
  # did is a patch naming no value.
  defp patch_entity(row, patch, verdicts) do
    data = WireData.patch(row.__struct__, patch)
    revisions = Map.take(row.__meta__.revisions, Map.keys(data))
    told = Map.put(data, :"$revisions", revisions)

    %{
      data: if(verdicts == nil, do: told, else: Map.put(told, :"$verdicts", verdicts)),
      id: row.id,
      op: :patch_entity,
      type: type_of(row)
    }
  end

  defp scope_payload(:all), do: %{scope: :all}

  defp scope_payload({:types, types}) do
    %{scope: :types, types: Enum.map(types, &Codec.encode_enum_value/1)}
  end

  defp payload(op, delta) when op in [:keep_hashed, :put_entity, :unsync_hashed], do: delta.data

  defp payload(:unsync_entity, delta), do: delta.id

  defp payload(_op_carrying_id_beside_data, delta), do: Map.put(delta.data, :id, delta.id)

  defp relationship(edge) do
    data = %{relationship: edge.relationship, target_id: edge.target_id}

    %{data: data, id: edge.entity_id, op: edge.op, type: Codec.encode_enum_value(edge.type)}
  end

  defp type_of(row) do
    Codec.encode_enum_value(row.__struct__)
  end
end
