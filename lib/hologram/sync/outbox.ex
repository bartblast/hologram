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
  #
  # Waiting chunks are then bounded by nothing, which a client that stops reading would turn into a
  # leak the cap used to bound. So the stream answers each chunk once it has written it, and no more
  # than a few go out unanswered: past them the session waits, so a fill's chunks go out only once
  # all but a few of those before them are written. A session waiting longer than a stream could
  # stay stuck with a live client on the other end gives up, and the client comes back through the
  # doors. A live client's own watchdog drops a stream that sent no heartbeat for two intervals, and
  # a stream stuck writing a chunk writes no heartbeat either, so the wait is twice that.
  #
  # The outbox also watches the client. A session is linked to the stream that started it, but over
  # HTTP/2 Bandit ends a stream's process with a normal exit, which takes nothing linked to it down:
  # the session would live on, waiting for answers from a stream that is gone.

  alias Hologram.Sync.Frame

  @max_unwritten 4
  @stall_ms 60_000

  defstruct [:client, :client_ref, :max_unwritten, :raw, :stall_ms, unwritten: 0]

  @type t :: %__MODULE__{
          client: pid,
          client_ref: reference,
          max_unwritten: pos_integer,
          raw: boolean,
          stall_ms: non_neg_integer,
          unwritten: non_neg_integer
        }

  @type message ::
          {:sync_deltas, String.t() | nil, list(map), non_neg_integer | nil,
           non_neg_integer | nil}
          | {:sync_synced, :all | {:types, list(module), non_neg_integer | nil}, String.t() | nil,
             non_neg_integer | nil}

  @doc """
  Returns an outbox sending to the given client, which it monitors from the calling process - the
  session - so the session hears of the client going, as a `:DOWN` carrying `:client_ref`.

  ## Options

    * `:max_unwritten` - how many chunks go out before the stream has answered that it wrote
      them. Defaults to `4`.
    * `:raw` - sends each message as the term it is, unencoded, and never waits for an answer.
      Only a test reading what a session tells wants it, since a test answers nothing. Defaults
      to `false`.
    * `:stall_ms` - how long a chunk waits for the stream to answer one written before it, in
      milliseconds, before the client is given up on. Defaults to `60_000`.
  """
  @spec new(pid, keyword) :: t
  def new(client, opts) do
    %__MODULE__{
      client: client,
      client_ref: Process.monitor(client),
      max_unwritten: Keyword.get(opts, :max_unwritten, @max_unwritten),
      raw: Keyword.get(opts, :raw, false),
      stall_ms: Keyword.get(opts, :stall_ms, @stall_ms)
    }
  end

  @doc """
  Sends the given message to the outbox's client, as `{:sync_frame, session, chunk}`: the SSE chunk
  carrying it, beside the session sending it, which the stream checks is the session it serves. A
  raw outbox sends the message itself.

  The stream answers `:sync_written` to the session for each chunk it writes. Every answer already
  waiting is taken first, and with `:max_unwritten` chunks still unanswered the message waits for
  the next answer. Waiting longer than `:stall_ms` answers `:stalled`, and the message is not sent.

  `:sync_stop` - the stream asking the session it no longer serves to stop - answers `:stopped`,
  whether it was waiting or arrives while the message does, and the message is not sent. So does
  the client going, which nothing would ever answer for.
  """
  @spec put(t, message) :: {:ok, t} | :stalled | :stopped
  def put(%__MODULE__{raw: true} = outbox, message) do
    send(outbox.client, message)

    {:ok, outbox}
  end

  def put(outbox, message) do
    with {:ok, answered} <- take_answers(outbox),
         {:ok, roomy} <- await_room(answered) do
      send(roomy.client, {:sync_frame, self(), encode(message)})

      {:ok, %{roomy | unwritten: roomy.unwritten + 1}}
    end
  end

  @doc """
  Counts one answer from the stream, for one that reached the session while nothing waited for it.
  """
  @spec written(t) :: t
  def written(outbox) do
    %{outbox | unwritten: max(outbox.unwritten - 1, 0)}
  end

  defp await_room(%{unwritten: unwritten, max_unwritten: max_unwritten} = outbox)
       when unwritten < max_unwritten do
    {:ok, outbox}
  end

  defp await_room(%{client_ref: client_ref} = outbox) do
    receive do
      :sync_written -> {:ok, written(outbox)}
      :sync_stop -> :stopped
      {:DOWN, ^client_ref, :process, _client, _reason} -> :stopped
    after
      outbox.stall_ms -> :stalled
    end
  end

  # The id is stamped here, when the frame is encoded, while the stream stamps its own events when
  # it writes them, so the ids on a stream do not rise in the order they are written. Nothing reads
  # them: no client asks for an event's id or hands one back.
  defp encode({:sync_deltas, cursor, deltas, applied_seq, final_seq}) do
    Frame.encode_deltas_envelope(event_id(), cursor, deltas, applied_seq, final_seq)
  end

  defp encode({:sync_synced, scope, cursor, final_seq}) do
    Frame.encode_synced_envelope(event_id(), scope, cursor, final_seq)
  end

  defp event_id, do: System.unique_integer([:positive, :monotonic])

  defp take_answers(%{client_ref: client_ref} = outbox) do
    receive do
      :sync_written -> take_answers(written(outbox))
      :sync_stop -> :stopped
      {:DOWN, ^client_ref, :process, _client, _reason} -> :stopped
    after
      0 -> {:ok, outbox}
    end
  end
end
