defmodule Hologram.Sync.Frame do
  @moduledoc false

  # What a client is sent, on the stream it already has open. Deltas ride beside the realtime
  # events as their own chunk kinds rather than on a connection of their own, so a tab keeps one
  # stream and sync inherits its handshake, heartbeats and reconnect.

  alias Hologram.Compiler.Encoder
  alias Hologram.Entity.Model

  @protocol_version 1

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
  Builds the SSE event-stream chunk saying the client now holds everything its page reads.

  Until it arrives the client answers from what the server rendered, because a store filled only
  part way would answer a query with part of the truth. What follows it is news rather than
  filling, so from here on the client can read its own store.
  """
  @spec encode_synced_envelope(integer) :: String.t()
  def encode_synced_envelope(id) do
    payload = %{protocol_version: @protocol_version}

    "event: synced\nid: #{id}\ndata: #{Encoder.encode_client_term!(payload)}\n\n"
  end

  @doc """
  Returns the protocol version this build speaks.
  """
  @spec protocol_version() :: pos_integer
  def protocol_version, do: @protocol_version
end
