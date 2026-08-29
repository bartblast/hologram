defmodule Hologram.Sync.Frame do
  @moduledoc false

  # What a client is sent, on the stream it already has open. Deltas ride beside the realtime
  # events as their own chunk kinds rather than on a connection of their own, so a tab keeps one
  # stream and sync inherits its handshake, heartbeats and reconnect.
  #
  # These four kinds carry JSON where every other chunk on that stream carries JavaScript source.
  # The others hand over arbitrary terms and need an encoder that can spell any of them - a delta
  # holds values a database stores, and paying ten times the bytes to say so, on the payload a
  # whole-app fill is mostly made of, buys nothing.

  alias Hologram.DB.Codec
  alias Hologram.Entity.Model
  alias Hologram.Sync.WireData

  @protocol_version 1

  @doc """
  Turns what a session worked out for one client into the deltas a frame carries.

  A row that appeared travels whole, because a client that did not have it needs all of it. A row
  that changed travels as the attributes that moved. A row that left travels as its id, and an
  edge as the pair it joined or parted.

  Every delta names its own type: an arrived row carries it, an edge carries the type of the row
  the relationship lives on, and a row that left arrives here as its id paired with the type it
  was held under - a row no longer there to be asked is named by the bookkeeping that watched it
  arrive.
  """
  @spec deltas(map) :: list(map)
  def deltas(news) do
    Enum.concat([
      Enum.map(news.appeared, &put_entity/1),
      Enum.map(news.patched, fn {row, patch} -> patch_entity(row, patch) end),
      Enum.map(news.unsynced, fn {id, entity_type} -> unsync_entity(id, entity_type) end),
      Enum.map(news.edges, &relationship/1)
    ])
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

  The scope says which queries it may now answer from its own store: `:page` covers the page it
  is on, `:all` covers every page, so navigating needs no server. Until a scope arrives the client
  answers from what the server rendered, because a store filled only part way would answer a query
  with part of the truth.

  Two scopes rather than one per window, because window ids are the server's business and never
  cross the wire - and "can I answer this page myself?" is the whole of what a client asks.
  """
  @spec encode_synced_envelope(integer, :all | :page) :: String.t()
  def encode_synced_envelope(id, scope) do
    payload = %{protocol_version: @protocol_version, scope: scope}

    "event: synced\nid: #{id}\ndata: #{Jason.encode!(payload)}\n\n"
  end

  @doc """
  Builds the SSE event-stream chunk telling a client to drop everything it holds, because what
  follows is the whole of what it may see rather than what changed.

  Sent when a returning client cannot be told what it missed - its place could not be read, the
  place predates the log, or the gap spans a change of model. The reason says which, for the sake
  of whoever is looking at why a client paid for a resync, and the client does the same thing
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
  Returns the protocol version this build speaks.
  """
  @spec protocol_version() :: pos_integer
  def protocol_version, do: @protocol_version

  @doc """
  Returns the delta handing a client a whole row, which is what a client that does not have it
  needs.
  """
  @spec put_entity(struct) :: map
  def put_entity(row) do
    %{data: WireData.row(row), id: row.id, op: :put_entity, type: type_of(row)}
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
  defp patch_entity(row, patch) do
    data = WireData.patch(row.__struct__, patch)
    revisions = Map.take(row.__meta__.revisions, Map.keys(data))

    %{
      data: Map.put(data, :"$revisions", revisions),
      id: row.id,
      op: :patch_entity,
      type: type_of(row)
    }
  end

  defp payload(:put_entity, delta), do: delta.data

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
