defmodule Hologram.Sync.Frame do
  @moduledoc false

  # What a client is sent, on the stream it already has open. Deltas ride beside the realtime
  # events as their own chunk kinds rather than on a connection of their own, so a tab keeps one
  # stream and sync inherits its handshake, heartbeats and reconnect.

  alias Hologram.Compiler.Encoder
  alias Hologram.DB.Codec
  alias Hologram.Entity.Model

  @protocol_version 1

  @doc """
  Turns what a session worked out for one client into the deltas a frame carries.

  A row that appeared travels whole, because a client that did not have it needs all of it. A row
  that changed travels as the attributes that moved. A row that left travels as its id, and an
  edge as the pair it joined or parted.

  The entity type is the window's own, which is what names the type of a row that is no longer
  there to be asked - a row that arrived carries its type with it.
  """
  @spec deltas(map, module) :: list(map)
  def deltas(news, entity_type) do
    window_type = Codec.encode_enum_value(entity_type)

    Enum.concat([
      Enum.map(news.appeared, &put_entity/1),
      Enum.map(news.patched, fn {row, patch} -> patch_entity(row, patch) end),
      Enum.map(news.unsynced, &unsync_entity(&1, window_type)),
      Enum.map(news.edges, &relationship(&1, window_type))
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
  """
  @spec encode_deltas_envelope(integer, String.t() | nil, list(map)) :: String.t()
  def encode_deltas_envelope(id, cursor, deltas) do
    payload = %{
      cursor: cursor,
      deltas: deltas,
      model_hash: Model.hash(),
      protocol_version: @protocol_version
    }

    "event: sync_deltas\nid: #{id}\ndata: #{Encoder.encode_client_term!(payload)}\n\n"
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

    "event: synced\nid: #{id}\ndata: #{Encoder.encode_client_term!(payload)}\n\n"
  end

  @doc """
  Builds the SSE event-stream chunk telling a client its bundle no longer matches this build.

  It is a notice rather than an order: the client reloads at a moment of its own choosing, since
  its store and its queued writes survive a reload and nothing is lost by waiting.
  """
  @spec encode_reload_envelope(integer, atom) :: String.t()
  def encode_reload_envelope(id, reason) do
    payload = %{protocol_version: @protocol_version, reason: reason}

    "event: sync_reload\nid: #{id}\ndata: #{Encoder.encode_client_term!(payload)}\n\n"
  end

  @doc """
  Returns the protocol version this build speaks.
  """
  @spec protocol_version() :: pos_integer
  def protocol_version, do: @protocol_version

  defp patch_entity(row, patch) do
    %{data: patch, id: row.id, op: :patch_entity, type: type_of(row)}
  end

  defp put_entity(row) do
    %{data: row, id: row.id, op: :put_entity, type: type_of(row)}
  end

  defp relationship(edge, window_type) do
    data = %{relationship: edge.relationship, target_id: edge.target_id}

    %{data: data, id: edge.entity_id, op: edge.op, type: window_type}
  end

  defp type_of(row) do
    Codec.encode_enum_value(row.__struct__)
  end

  defp unsync_entity(id, window_type) do
    %{id: id, op: :unsync_entity, type: window_type}
  end
end
