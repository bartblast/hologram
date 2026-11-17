defmodule Hologram.Sync.Outbox do
  @moduledoc false

  # What a session tells its client goes out through here, encoded into the chunk the client's SSE
  # stream writes as it is. Encoded in the session rather than in the stream, because the stream's
  # process runs under a heap cap meant for broadcasts piling up behind a slow consumer (see
  # `Hologram.Realtime.SSE.configure_backpressure_safety_net/0`). A frame of 500 rows takes about
  # ten times its own size on the heap while it is encoded, and a fill sends many at once: encoded
  # in the stream, they passed the cap and the stream was killed mid-fill. A chunk is a binary too
  # big to live on a process heap, so the stream holds a reference to it and nothing more, however
  # big it is and however many are waiting.

  alias Hologram.Sync.Frame

  defstruct [:client, :raw]

  @type t :: %__MODULE__{client: pid, raw: boolean}

  @type message ::
          {:sync_deltas, String.t() | nil, list(map), non_neg_integer | nil}
          | {:sync_synced, :all | {:types, list(module)}, String.t() | nil}

  @doc """
  Returns an outbox sending to the given client.

  ## Options

    * `:raw` - sends each message as the term it is, unencoded. Only a test reading what a session
      tells wants it. Defaults to `false`.
  """
  @spec new(pid, keyword) :: t
  def new(client, opts) do
    %__MODULE__{client: client, raw: Keyword.get(opts, :raw, false)}
  end

  @doc """
  Sends the given message to the outbox's client, as `{:sync_frame, session, chunk}`: the SSE chunk
  carrying it, beside the session sending it, which the stream checks is the session it serves. A
  raw outbox sends the message itself.
  """
  @spec put(t, message) :: :ok
  def put(%__MODULE__{raw: true} = outbox, message) do
    send(outbox.client, message)

    :ok
  end

  def put(outbox, message) do
    send(outbox.client, {:sync_frame, self(), encode(message)})

    :ok
  end

  # The id is stamped here, when the frame is encoded, while the stream stamps its own events when
  # it writes them, so the ids on a stream do not rise in the order they are written. Nothing reads
  # them: no client asks for an event's id or hands one back.
  defp encode({:sync_deltas, cursor, deltas, applied_seq}) do
    Frame.encode_deltas_envelope(event_id(), cursor, deltas, applied_seq)
  end

  defp encode({:sync_synced, scope, cursor}) do
    Frame.encode_synced_envelope(event_id(), scope, cursor)
  end

  defp event_id, do: System.unique_integer([:positive, :monotonic])
end
