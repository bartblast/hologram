defmodule HologramSyncBenchmark.Client do
  @moduledoc false

  # One fake browser tab: a syncing SSE stream, connected the way the browser connects
  # (Hologram.Test.SyncClient does the same over :httpc). One process and one Mint connection per
  # client: :httpc runs every request through one manager process per profile, a bottleneck at
  # thousands of streams.
  #
  # Kept cheap on purpose, since it shares the machine with the server node: a chunk is matched
  # against a few byte patterns and never decoded. What it records is when things arrived, read
  # by the driver on request rather than streamed to it.

  use GenServer

  alias Hologram.Test.SyncClient

  # The TCP connect and each read of an answer wait at most this long, so a server that stops
  # answering ends the attempt and the calls below can wait without a timeout of their own.
  @io_timeout_ms 30_000

  @connect_attempts 5

  @connect_backoff_ms 100

  # The newline is part of each pattern: JSON escapes it, so no row value can spell one.
  @failure_patterns %{
    "event: sync_reload\n" => :sync_reload,
    "event: sync_resync\n" => :sync_resync
  }

  # Unique to the `synced` frame of the whole pot: no other frame carries a scope, and a row value
  # holding these characters travels with its quotes escaped.
  @synced_all_pattern ~s("scope":"all")

  # The frame handing a client the rules the server enforces, sent when the greeting named others.
  @rules_pattern "event: sync_rules\n"

  # Where a frame names the place in the log it leaves the client at, up to the closing quote. A
  # place is digits, dots and hex, so nothing in it is escaped, and a row value holding these
  # characters travels with its quotes escaped.
  @cursor_prefix ~s("cursor":")

  # The prefix, a transaction id of 20 digits, a sequence number of 19, two hashes of 32
  # characters, the three dots between them and the closing quote.
  @max_cursor_bytes 117

  # A timed write sets a column to a marker, the prefix and a number of a fixed width (see
  # marker/1), and a client records when it first saw each one. Seeded values never start with
  # the prefix.
  @marker_prefix "wmk"

  @marker_digits 7

  # The blank line ending every frame. A browser only takes a frame whole, so what's matched inside
  # one is recorded once its end arrives, at that chunk's time. JSON escapes newlines, so no row
  # value can spell it.
  @frame_end "\n\n"

  @patterns [
    @cursor_prefix,
    @frame_end,
    @marker_prefix,
    @rules_pattern,
    @synced_all_pattern | Map.keys(@failure_patterns)
  ]

  # What of the previous chunk is kept, so a pattern split across two reads is still found: one
  # byte short of the longest thing matched, a marker counted whole. A shorter one can lie wholly
  # inside it, so a match ending there was already taken with the previous chunk and is skipped.
  @carry_bytes Enum.max([
                 @max_cursor_bytes,
                 byte_size(@marker_prefix) + @marker_digits | Enum.map(@patterns, &byte_size/1)
               ]) - 1

  # How long a stream has to have lasted for the browser to start its reconnect delay over.
  @reconnect_reset_ms 5_000

  # The browser's own reconnect delay (assets/js/sse.mjs): 250 ms doubling up to 5 s, with 25%
  # jitter either way.
  @reconnect_base_ms 250

  @reconnect_max_ms 5_000

  @reconnect_jitter 0.25

  @type report :: %{
          bytes: non_neg_integer,
          bytes_at_leave: non_neg_integer | nil,
          caught_up_at: integer | nil,
          connect_retries: non_neg_integer,
          connected_at: integer | nil,
          counted: %{put: non_neg_integer, unsync: non_neg_integer},
          counted_at: %{put: integer | nil, unsync: integer | nil},
          failure: term | nil,
          markers: %{non_neg_integer => integer},
          restarts: non_neg_integer,
          return_restarts: non_neg_integer,
          returned_at: integer | nil,
          rules_at: integer | nil,
          synced_all_at: integer | nil
        }

  @doc """
  Closes the client's stream and stops it, returning :ok.
  """
  @spec close(pid) :: :ok
  def close(client) do
    GenServer.stop(client, :normal)
  end

  @doc """
  Has a client that left come back after the given milliseconds, opening its stream with the last
  place it was told, and returns :ok, or `{:error, :not_away}` for one that didn't leave.

  `:returned_at` in its report is when it opens the stream and `:caught_up_at` the `synced` frame
  for the whole pot after that. A failed open and a stream lost before that frame are tried again
  on the browser's delay, with the latest place, and counted in `:return_restarts`.
  """
  @spec come_back(pid, non_neg_integer) :: :ok | {:error, :not_away}
  def come_back(client, delay_ms) do
    GenServer.call(client, {:come_back, delay_ms}, :infinity)
  end

  @doc """
  Opens the client's sync stream and returns :ok once the server answered it, or `{:error,
  reason}`.

  Timed from here: the handshake and the stream request, what a browser that already holds its
  session cookie does when it reconnects. A connection the server refuses or resets is tried
  again, up to #{@connect_attempts} times, and the retries are counted in the report.
  """
  @spec connect(pid) :: :ok | {:error, term}
  def connect(client) do
    GenServer.call(client, :connect, :infinity)
  end

  @doc """
  Returns whether the client has seen the marker with the given number, cheaper to ask than a
  whole report while a step waits on a write.
  """
  @spec has_marker?(pid, non_neg_integer) :: boolean
  def has_marker?(client, number) do
    GenServer.call(client, {:has_marker?, number}, :infinity)
  end

  @doc """
  Closes the stream of a client holding its whole pot, the way a deploy closes it, and keeps what
  the client knows, returning :ok. A client leaves once. One that hasn't filled, has failed or left
  before answers `{:error, reason}`.
  """
  @spec leave(pid) :: :ok | {:error, term}
  def leave(client) do
    GenServer.call(client, :leave, :infinity)
  end

  @doc """
  Returns the marker a timed write with the given number sets, which a client records when it
  first sees.
  """
  @spec marker(non_neg_integer) :: String.t()
  def marker(number) do
    digits =
      number
      |> Integer.to_string()
      |> String.pad_leading(@marker_digits, "0")

    @marker_prefix <> digits
  end

  @doc """
  Fetches the client's session cookie, returning :ok or `{:error, reason}`.

  Untimed: the request renders a page on the server, which isn't sync, and a browser coming back
  after a deploy already holds its cookie.
  """
  @spec prepare(pid) :: :ok | {:error, term}
  def prepare(client) do
    GenServer.call(client, :prepare, :infinity)
  end

  @doc """
  Returns what the client has recorded so far. Times are `:os.system_time(:microsecond)`, the
  clock the server node reads too.

  `:connected_at` is the first connect and `:synced_all_at` the `synced` frame for the whole pot,
  so their difference is the fill as the user waits for it, restarts included. `:markers` maps
  each timed write's number to when it first arrived.
  """
  @spec report(pid) :: report
  def report(client) do
    # A client opening its stream again is busy in that call for as long as the server takes to
    # answer, so a report can wait.
    GenServer.call(client, :report, :infinity)
  end

  @doc """
  Starts a client that hasn't connected yet.

  `:policy_hash` is the hash of the rules the client's bundle was built with, absent for one
  holding the current ones.

  `:count_type` names an entity type, as `inspect/1` spells its module, whose `put_entity` and
  `unsync_entity` deltas the client counts, decoding every `sync_deltas` frame for it. Costly, so
  only for a case that needs to know when every row of a big change has arrived.

  A stream that ends before the whole pot arrived is opened again after the browser's delay, the
  way a browser starts a fill over, and counted in `:restarts`: the server cutting a fill short
  is a cost a user pays, not a failure of the run. A stream that ends after the fill fails the
  client, unless it left (see `leave/1`) or is still catching up after coming back (see
  `come_back/2`).

  Options: `:base_url`, `:cookie_path` (the page whose render hands out the session cookie, and
  signs the client in when it's a sign-in path), and the greeting: `:page`, and the server's
  `:model_hash` and `:protocol_version`, read from the server node since the driver never boots
  Hologram. The greeting is built here rather than by `Hologram.Test.SyncClient.greeting_params/1`,
  which hashes the model it runs in.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl GenServer
  def init(opts) do
    uri =
      opts
      |> Keyword.fetch!(:base_url)
      |> URI.parse()

    state = %{
      away: false,
      bytes: 0,
      bytes_at_leave: nil,
      carry: "",
      caught_up_at: nil,
      conn: nil,
      connect_retries: 0,
      connected_at: nil,
      cookie: nil,
      cookie_path: Keyword.fetch!(opts, :cookie_path),
      count_type: Keyword.get(opts, :count_type),
      counted: %{put: 0, unsync: 0},
      counted_at: %{put: nil, unsync: nil},
      cursor: nil,
      failure: nil,
      frames: "",
      greeting: greeting(opts),
      host: uri.host,
      markers: %{},
      pending: [],
      port: uri.port,
      reconnect_attempt: 0,
      request_ref: nil,
      restarts: 0,
      return_restarts: 0,
      returned_at: nil,
      rules_at: nil,
      stream_opened_at: nil,
      synced_all_at: nil
    }

    {:ok, state}
  end

  @impl GenServer
  def handle_call(:prepare, _from, state) do
    case fetch_cookie(state) do
      {:ok, cookie} -> {:reply, :ok, %{state | cookie: cookie}}
      {:error, reason} -> {:reply, {:error, reason}, %{state | failure: {:prepare, reason}}}
    end
  end

  def handle_call(:connect, _from, %{connected_at: nil} = state) do
    state = %{state | connected_at: now()}

    case open_stream(state, 1) do
      {:ok, state} ->
        {:reply, :ok, state}

      {:error, reason, state} ->
        {:reply, {:error, reason}, %{state | failure: {:connect, reason}}}
    end
  end

  # A client connects once, whether that worked or not: a second run's times would mix with the
  # first one's.
  def handle_call(:connect, _from, state) do
    {:reply, {:error, :connected_before}, state}
  end

  def handle_call(
        :leave,
        _from,
        %{bytes_at_leave: nil, failure: nil, synced_all_at: synced_all_at} = state
      )
      when synced_all_at != nil do
    if state.conn, do: Mint.HTTP.close(state.conn)

    left = %{
      state
      | away: true,
        bytes_at_leave: state.bytes,
        carry: "",
        conn: nil,
        frames: "",
        pending: [],
        # Worked out here, since the time away would count as the stream's age later. Coming back
        # is the browser's next retry after losing this stream, so one that fails waits one step
        # further.
        reconnect_attempt: attempt_after_stream(state) + 1,
        request_ref: nil
    }

    {:reply, :ok, left}
  end

  def handle_call(:leave, _from, state) do
    {:reply, {:error, state.failure || :cannot_leave}, state}
  end

  def handle_call({:come_back, delay_ms}, _from, %{away: true} = state) do
    Process.send_after(self(), :come_back, delay_ms)

    {:reply, :ok, %{state | away: false}}
  end

  def handle_call({:come_back, _delay_ms}, _from, state) do
    {:reply, {:error, :not_away}, state}
  end

  def handle_call({:has_marker?, number}, _from, state) do
    {:reply, Map.has_key?(state.markers, number), state}
  end

  def handle_call(:report, _from, state) do
    report =
      Map.take(state, [
        :bytes,
        :bytes_at_leave,
        :caught_up_at,
        :connect_retries,
        :connected_at,
        :counted,
        :counted_at,
        :failure,
        :markers,
        :restarts,
        :return_restarts,
        :returned_at,
        :rules_at,
        :synced_all_at
      ])

    {:reply, report, state}
  end

  @impl GenServer
  def handle_info(:come_back, %{conn: nil} = state) do
    reopen(%{state | returned_at: now()})
  end

  # Tried again until the driver gives up on the fill, the way a browser keeps trying: what the
  # server refuses mid-fill is part of the cost a fill has.
  def handle_info(:reconnect, %{conn: nil} = state), do: reopen(state)

  def handle_info(message, %{conn: conn} = state) when conn != nil do
    case Mint.HTTP.stream(conn, message) do
      {:ok, conn, responses} ->
        {:noreply, handle_responses(%{state | conn: conn}, responses, now())}

      {:error, conn, reason, responses} ->
        state = handle_responses(%{state | conn: conn}, responses, now())

        {:noreply, lose_stream(state, {:stream_error, reason})}

      :unknown ->
        {:noreply, state}
    end
  end

  def handle_info(_message, state), do: {:noreply, state}

  @impl GenServer
  def terminate(_reason, %{conn: conn}) when conn != nil do
    Mint.HTTP.close(conn)
  end

  def terminate(_reason, _state), do: :ok

  defp fail(%{failure: nil} = state, reason), do: %{state | failure: reason}

  defp fail(state, _reason), do: state

  # Already lost, by an earlier response of the same read.
  defp lose_stream(%{conn: nil} = state, _reason), do: state

  defp lose_stream(%{failure: nil, synced_all_at: nil} = state, _reason) do
    restart_stream(%{state | restarts: state.restarts + 1})
  end

  defp lose_stream(%{caught_up_at: nil, failure: nil, returned_at: returned_at} = state, _reason)
       when returned_at != nil do
    restart_stream(%{state | return_restarts: state.return_restarts + 1})
  end

  defp lose_stream(state, reason), do: fail(state, reason)

  defp restart_stream(state) do
    Mint.HTTP.close(state.conn)

    schedule_reconnect(%{
      state
      | carry: "",
        conn: nil,
        frames: "",
        pending: [],
        reconnect_attempt: attempt_after_stream(state),
        request_ref: nil
    })
  end

  # A stream that lasted starts the delay over, as the browser's does.
  defp attempt_after_stream(state) do
    if now() - state.stream_opened_at >= @reconnect_reset_ms * 1_000,
      do: 0,
      else: state.reconnect_attempt
  end

  # A returning client gets no quick retries: a browser waits out its delay after every refused
  # connection, and a wave overflowing the listen backlog is what's being measured.
  defp reopen(state) do
    first_attempt = if state.returned_at, do: @connect_attempts, else: 1

    case open_stream(state, first_attempt) do
      {:ok, opened} -> {:noreply, opened}
      {:error, _reason, failed} -> {:noreply, schedule_reconnect(count_failed_return(failed))}
    end
  end

  defp count_failed_return(%{returned_at: nil} = state), do: state

  defp count_failed_return(state) do
    %{state | return_restarts: state.return_restarts + 1}
  end

  defp schedule_reconnect(state) do
    attempt = state.reconnect_attempt + 1
    Process.send_after(self(), :reconnect, reconnect_delay_ms(attempt))

    %{state | reconnect_attempt: attempt}
  end

  defp reconnect_delay_ms(attempt) do
    base = min(@reconnect_base_ms * Integer.pow(2, attempt - 1), @reconnect_max_ms)
    jitter = base * @reconnect_jitter * (2 * :rand.uniform() - 1)

    round(base + jitter)
  end

  # A chunk is matched with the tail of the one before it, so a pattern split across two TCP reads
  # is still found, in one pass over the chunk for every pattern.
  defp handle_chunk(state, chunk, received_at) do
    old_carry_size = byte_size(state.carry)
    joined = state.carry <> chunk
    carry_size = min(byte_size(joined), @carry_bytes)

    # Copied, since a part of `joined` would keep the whole chunk alive until the next one.
    carry =
      joined
      |> binary_part(byte_size(joined) - carry_size, carry_size)
      |> :binary.copy()

    state =
      joined
      |> :binary.matches(patterns())
      |> Enum.map(fn {start, length} -> {start, match_size(joined, start, length)} end)
      |> Enum.filter(fn {start, size} ->
        start + size > old_carry_size and start + size <= byte_size(joined)
      end)
      |> Enum.reduce(state, fn {start, size}, acc ->
        hold_match(acc, binary_part(joined, start, size), received_at)
      end)

    state
    |> count_deltas(chunk, received_at)
    |> Map.merge(%{bytes: state.bytes + byte_size(chunk), carry: carry})
  end

  defp count_deltas(%{count_type: nil} = state, _chunk, _received_at), do: state

  # Frames are split on the blank line that ends each, the partial last one kept for the next
  # chunk, which is what Hologram.Test.SyncClient.parse_frames/1 does.
  defp count_deltas(state, chunk, received_at) do
    {frames, rest} = SyncClient.parse_frames(state.frames <> chunk)

    frames
    |> Enum.filter(&(&1["event"] == "sync_deltas"))
    |> Enum.reduce(%{state | frames: rest}, &count_frame(&2, &1, received_at))
  end

  defp count_frame(state, frame, received_at) do
    deltas = Jason.decode!(frame["data"])["deltas"]

    Enum.reduce([put: "put_entity", unsync: "unsync_entity"], state, fn {kind, op}, acc ->
      case count_of_type(deltas[op], acc.count_type) do
        0 ->
          acc

        count ->
          %{
            acc
            | counted: Map.update!(acc.counted, kind, &(&1 + count)),
              counted_at: Map.put(acc.counted_at, kind, received_at)
          }
      end
    end)
  end

  defp count_of_type(nil, _type), do: 0

  defp count_of_type(grouped, type) do
    Enum.sum_by(grouped, fn {name, rows} ->
      if name == type, do: length(rows), else: 0
    end)
  end

  # Compiled once per client process and kept in its dictionary, since a compiled pattern can't
  # be a module attribute.
  defp patterns do
    case Process.get(:patterns) do
      nil ->
        compiled = :binary.compile_pattern(@patterns)
        Process.put(:patterns, compiled)
        compiled

      compiled ->
        compiled
    end
  end

  # A marker is its prefix and the digits after it, and a cursor its prefix and everything up to
  # the closing quote. One that hasn't arrived whole is dropped here and found whole in the next
  # chunk, since it starts inside the carry.
  defp match_size(joined, start, length) do
    case binary_part(joined, start, length) do
      @marker_prefix -> length + @marker_digits
      @cursor_prefix -> cursor_size(joined, start, length)
      _other -> length
    end
  end

  defp cursor_size(joined, start, prefix_size) do
    value_start = start + prefix_size
    scope_size = min(@max_cursor_bytes - prefix_size, byte_size(joined) - value_start)

    case :binary.match(joined, "\"", scope: {value_start, scope_size}) do
      {quote_at, 1} -> quote_at + 1 - start
      :nomatch -> byte_size(joined) - start + 1
    end
  end

  # Matches wait for their frame's end, in the order they came. A failure is taken at once: it's
  # what the server said, whether or not the frame ever completes.
  defp hold_match(state, @frame_end, received_at) do
    state.pending
    |> Enum.reverse()
    |> Enum.reduce(%{state | pending: []}, &take_match(&2, &1, received_at))
  end

  defp hold_match(state, match, received_at) when is_map_key(@failure_patterns, match),
    do: take_match(state, match, received_at)

  defp hold_match(state, match, _received_at), do: %{state | pending: [match | state.pending]}

  defp take_match(state, @marker_prefix <> digits, received_at) do
    case Integer.parse(digits) do
      {number, ""} -> %{state | markers: Map.put_new(state.markers, number, received_at)}
      _not_a_marker -> state
    end
  end

  # Copied, since a part of the chunk would keep the whole chunk alive for as long as the client.
  defp take_match(state, @cursor_prefix <> quoted, _received_at) do
    cursor =
      quoted
      |> binary_part(0, byte_size(quoted) - 1)
      |> :binary.copy()

    %{state | cursor: cursor}
  end

  # The browser greets with the rules it was handed from then on, which naming none stands for.
  defp take_match(state, @rules_pattern, received_at) do
    %{
      state
      | greeting: List.keydelete(state.greeting, :policy_hash, 0),
        rules_at: state.rules_at || received_at
    }
  end

  defp take_match(%{synced_all_at: nil} = state, @synced_all_pattern, received_at) do
    %{state | synced_all_at: received_at}
  end

  defp take_match(
         %{caught_up_at: nil, returned_at: returned_at} = state,
         @synced_all_pattern,
         received_at
       )
       when returned_at != nil do
    %{state | caught_up_at: received_at}
  end

  defp take_match(state, @synced_all_pattern, _received_at), do: state

  defp take_match(state, failure_pattern, _received_at) do
    fail(state, Map.fetch!(@failure_patterns, failure_pattern))
  end

  defp handle_responses(state, responses, received_at) do
    Enum.reduce(responses, state, fn
      {:data, ref, chunk}, %{request_ref: ref} = state ->
        handle_chunk(state, chunk, received_at)

      {:done, ref}, %{request_ref: ref} = state ->
        lose_stream(state, :stream_ended)

      {:error, ref, reason}, %{request_ref: ref} = state ->
        lose_stream(state, {:stream_error, reason})

      _other, state ->
        state
    end)
  end

  defp fetch_cookie(state) do
    with {:ok, conn} <- open_connection(state),
         {:ok, conn, ref} <- Mint.HTTP.request(conn, "GET", state.cookie_path, [], nil),
         {:ok, conn, %{status: 200, headers: headers}} <- receive_response(conn, ref) do
      Mint.HTTP.close(conn)

      cookies =
        for {"set-cookie", value} <- headers do
          value
          |> String.split(";")
          |> hd()
        end

      # Caught here rather than as the handshake's refusal later, which wouldn't say why.
      if cookies == [], do: {:error, :no_session_cookie}, else: {:ok, Enum.join(cookies, "; ")}
    else
      {:ok, conn, %{status: status}} ->
        Mint.HTTP.close(conn)
        {:error, {:status, status}}

      {:error, reason} ->
        {:error, reason}

      {:error, conn, reason} ->
        Mint.HTTP.close(conn)
        {:error, reason}
    end
  end

  # A `:policy_hash` travels only when given: a client naming none is served as one holding the
  # current rules, and one naming others is sent the server's.
  defp greeting(opts) do
    base = Enum.map([:model_hash, :page, :protocol_version], &{&1, Keyword.fetch!(opts, &1)})

    case Keyword.get(opts, :policy_hash) do
      nil -> base
      policy_hash -> [{:policy_hash, policy_hash} | base]
    end
  end

  defp handshake_body(instance_id) do
    instance_id_hex = Base.encode16(instance_id, case: :lower)

    Jason.encode!([
      2,
      %{
        "t" => "m",
        "d" => [
          ["ainstance_id", "b0#{instance_id_hex}"],
          ["areceipts", %{"t" => "l", "d" => []}]
        ]
      }
    ])
  end

  defp now, do: :os.system_time(:microsecond)

  defp open_connection(state) do
    Mint.HTTP.connect(:http, state.host, state.port,
      mode: :passive,
      transport_opts: [timeout: @io_timeout_ms]
    )
  end

  # The handshake and the stream ride one connection, as a browser's do. The connection is passive
  # until the stream's headers are in, so each answer is read in place, then active, so chunks
  # arrive as messages.
  defp open_stream(state, attempt) do
    instance_id = "bench-client-#{System.unique_integer([:positive])}"
    cookie_header = [{"cookie", state.cookie}]

    with {:ok, conn} <- open_connection(state),
         {:ok, conn, handshake_id} <- redeem_handshake(conn, cookie_header, instance_id),
         params =
           state.greeting ++
             cursor_param(state) ++ [handshake_id: handshake_id, instance_id: instance_id],
         {:ok, conn, ref, early_chunks} <- request_stream(conn, cookie_header, params) do
      received_at = now()
      state = %{state | conn: conn, request_ref: ref, stream_opened_at: received_at}

      {:ok, Enum.reduce(early_chunks, state, &handle_chunk(&2, &1, received_at))}
    else
      {:error, reason} -> retry_or_fail(state, attempt, reason, nil)
      {:error, conn, reason} -> retry_or_fail(state, attempt, reason, conn)
    end
  end

  # Only a client holding a whole pot has a place, so one restarting its first fill greets with
  # none and is filled from nothing, as a browser is.
  defp cursor_param(%{cursor: nil}), do: []

  defp cursor_param(%{cursor: cursor}), do: [cursor: cursor]

  defp receive_response(conn, ref, response \\ %{body: [], headers: [], status: nil}) do
    case Mint.HTTP.recv(conn, 0, @io_timeout_ms) do
      {:ok, conn, responses} ->
        case Enum.reduce(responses, response, &take_response(&1, &2, ref)) do
          {:done, response} -> {:ok, conn, %{response | body: IO.iodata_to_binary(response.body)}}
          response -> receive_response(conn, ref, response)
        end

      {:error, conn, reason, _responses} ->
        {:error, conn, reason}
    end
  end

  defp redeem_handshake(conn, cookie_header, instance_id) do
    headers = [{"content-type", "application/json"} | cookie_header]
    body = handshake_body(instance_id)

    with {:ok, conn, ref} <-
           Mint.HTTP.request(conn, "POST", "/hologram/sse/handshake", headers, body),
         {:ok, conn, %{status: 200, body: response_body}} <- receive_response(conn, ref) do
      handshake_id =
        response_body
        |> Jason.decode!()
        |> Map.fetch!("handshakeId")

      {:ok, conn, handshake_id}
    else
      {:ok, conn, %{status: status}} -> {:error, conn, {:handshake_status, status}}
      error -> error
    end
  end

  # Returns the chunks that arrived with the headers too, since the stream's first frames can come
  # in the same read.
  defp request_stream(conn, cookie_header, params) do
    path = "/hologram/sse?" <> URI.encode_query(params)

    with {:ok, conn, ref} <- Mint.HTTP.request(conn, "GET", path, cookie_header, nil),
         {:ok, conn, %{status: 200, ended: false, body: chunks}} <-
           await_stream_headers(conn, ref),
         {:ok, conn} <- set_active(conn) do
      {:ok, conn, ref, Enum.reverse(chunks)}
    else
      {:ok, conn, %{status: 200}} -> {:error, conn, :stream_ended}
      {:ok, conn, %{status: status}} -> {:error, conn, {:stream_status, status}}
      error -> error
    end
  end

  # Mint answers a failed switch without the connection, which is still open and has to be closed.
  defp set_active(conn) do
    case Mint.HTTP.set_mode(conn, :active) do
      {:ok, conn} -> {:ok, conn}
      {:error, reason} -> {:error, conn, reason}
    end
  end

  defp await_stream_headers(
         conn,
         ref,
         response \\ %{body: [], ended: false, headers: nil, status: nil}
       ) do
    case Mint.HTTP.recv(conn, 0, @io_timeout_ms) do
      {:ok, conn, responses} ->
        response = Enum.reduce(responses, response, &take_stream_response(&1, &2, ref))

        if response.headers,
          do: {:ok, conn, response},
          else: await_stream_headers(conn, ref, response)

      {:error, conn, reason, _responses} ->
        {:error, conn, reason}
    end
  end

  defp take_stream_response({:status, ref, status}, response, ref),
    do: %{response | status: status}

  defp take_stream_response({:headers, ref, headers}, response, ref),
    do: %{response | headers: headers}

  defp take_stream_response({:data, ref, data}, response, ref),
    do: %{response | body: [data | response.body]}

  # The server ending the stream in the same read as its headers.
  defp take_stream_response({:done, ref}, response, ref), do: %{response | ended: true}

  defp take_stream_response({:error, ref, _reason}, response, ref), do: %{response | ended: true}

  defp take_stream_response(_other, response, _ref), do: response

  defp retry_or_fail(state, attempt, reason, conn) do
    if conn, do: Mint.HTTP.close(conn)

    if attempt < @connect_attempts and retryable?(reason) do
      Process.sleep(@connect_backoff_ms * attempt)
      open_stream(%{state | connect_retries: state.connect_retries + 1}, attempt + 1)
    else
      {:error, reason, state}
    end
  end

  defp retryable?(%Mint.TransportError{reason: reason}),
    do: reason in [:closed, :econnrefused, :econnreset]

  defp retryable?(_reason), do: false

  defp take_response(_response, {:done, _response_so_far} = done, _ref), do: done

  defp take_response({:status, ref, status}, response, ref), do: %{response | status: status}

  defp take_response({:headers, ref, headers}, response, ref) do
    %{response | headers: response.headers ++ headers}
  end

  defp take_response({:data, ref, data}, response, ref),
    do: %{response | body: [response.body, data]}

  defp take_response({:done, ref}, response, ref), do: {:done, response}

  defp take_response(_other, response, _ref), do: response
end
