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

  @patterns [@synced_all_pattern | Map.keys(@failure_patterns)]

  # What of the previous chunk is kept, so a pattern split across two reads is still found: one
  # byte short of the longest pattern. A shorter pattern can lie wholly inside it, so a match
  # ending there was already taken with the previous chunk and is skipped.
  @carry_bytes (@patterns
                |> Enum.map(&byte_size/1)
                |> Enum.max()) - 1

  @type report :: %{
          bytes: non_neg_integer,
          connect_retries: non_neg_integer,
          connected_at: integer | nil,
          failure: term | nil,
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
  """
  @spec report(pid) :: report
  def report(client) do
    GenServer.call(client, :report)
  end

  @doc """
  Starts a client that hasn't connected yet.

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
      bytes: 0,
      carry: "",
      conn: nil,
      connect_retries: 0,
      connected_at: nil,
      cookie: nil,
      cookie_path: Keyword.fetch!(opts, :cookie_path),
      failure: nil,
      greeting:
        Enum.map([:model_hash, :page, :protocol_version], &{&1, Keyword.fetch!(opts, &1)}),
      host: uri.host,
      port: uri.port,
      request_ref: nil,
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

  def handle_call(:report, _from, state) do
    report = Map.take(state, [:bytes, :connect_retries, :connected_at, :failure, :synced_all_at])

    {:reply, report, state}
  end

  @impl GenServer
  def handle_info(message, %{conn: conn} = state) when conn != nil do
    case Mint.HTTP.stream(conn, message) do
      {:ok, conn, responses} ->
        {:noreply, handle_responses(%{state | conn: conn}, responses, now())}

      {:error, conn, reason, responses} ->
        state = handle_responses(%{state | conn: conn}, responses, now())

        {:noreply, fail(state, {:stream_error, reason})}

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
      |> Enum.reject(fn {start, length} -> start + length <= old_carry_size end)
      |> Enum.reduce(state, fn {start, length}, acc ->
        take_match(acc, binary_part(joined, start, length), received_at)
      end)

    %{state | bytes: state.bytes + byte_size(chunk), carry: carry}
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

  defp take_match(%{synced_all_at: nil} = state, @synced_all_pattern, received_at) do
    %{state | synced_all_at: received_at}
  end

  defp take_match(state, @synced_all_pattern, _received_at), do: state

  defp take_match(state, failure_pattern, _received_at) do
    fail(state, Map.fetch!(@failure_patterns, failure_pattern))
  end

  defp handle_responses(state, responses, received_at) do
    Enum.reduce(responses, state, fn
      {:data, ref, chunk}, %{request_ref: ref} = state -> handle_chunk(state, chunk, received_at)
      {:done, ref}, %{request_ref: ref} = state -> fail(state, :stream_ended)
      {:error, ref, reason}, %{request_ref: ref} = state -> fail(state, {:stream_error, reason})
      _other, state -> state
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
         params = state.greeting ++ [handshake_id: handshake_id, instance_id: instance_id],
         {:ok, conn, ref, early_chunks} <- request_stream(conn, cookie_header, params) do
      state = %{state | conn: conn, request_ref: ref}
      received_at = now()

      {:ok, Enum.reduce(early_chunks, state, &handle_chunk(&2, &1, received_at))}
    else
      {:error, reason} -> retry_or_fail(state, attempt, reason, nil)
      {:error, conn, reason} -> retry_or_fail(state, attempt, reason, conn)
    end
  end

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
