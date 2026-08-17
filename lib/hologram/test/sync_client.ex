defmodule Hologram.Test.SyncClient do
  @moduledoc false

  # A sync client that is not a browser, for tests that assert on the wire itself. A browser's
  # EventSource drops every event its page registered no listener for, so it can only show what
  # the client already understands - this connects the way the browser does (session cookie,
  # handshake redemption, SSE GET with the sync greeting) and hands frames over raw.
  #
  # Consumed by the feature and cluster test apps, like FeatureHelpers beside it. Built on
  # :httpc so it adds no dependency to either.

  alias Hologram.Entity.Model
  alias Hologram.Sync.Frame

  defstruct buffer: "", frames: [], request_id: nil

  @type t :: %__MODULE__{buffer: String.t(), frames: list(map), request_id: reference | nil}

  @doc """
  Returns the next frame of the given SSE event kind, with the client to keep reading from.

  Frames of other kinds arriving first are passed over and dropped. Raises when the stream ends,
  or when nothing of the kind arrives within `timeout_ms` - a test waiting on a frame that never
  comes should say so rather than time the suite out.
  """
  @spec await_frame(t, String.t(), non_neg_integer) :: {map, t}
  def await_frame(client, event_name, timeout_ms \\ 5_000) do
    case next_frame(client, event_name, timeout_ms) do
      {:ok, frame, client} -> {frame, client}
      {:timeout, _client} -> raise "no #{inspect(event_name)} frame arrived within the timeout"
    end
  end

  @doc """
  Closes the client's stream.

  Worth doing rather than leaving to the test's exit: the server holds a session and its
  evaluators open for as long as the connection is, and the next test would be served what this
  one left behind.
  """
  @spec close(t) :: :ok
  def close(client) do
    :httpc.cancel_request(client.request_id)
  end

  @doc """
  Opens a syncing SSE connection to the given base URL and returns the client to read frames
  from.

  What the browser does, done directly: GET `:cookie_path` for the session cookie, POST the
  handshake, then GET the SSE stream carrying the sync greeting. The greeting's `:model_hash`
  and `:protocol_version` default to this build's own - a test speaking as a stale client
  overrides them - and `:page` names the page the client claims to be on. `:cursor` is the place
  a returning client hands back, absent for a first visit.
  """
  @spec connect(String.t(), keyword) :: t
  def connect(base_url, opts) do
    {:ok, _apps} = Application.ensure_all_started(:inets)

    cookie =
      base_url
      |> fetch_session_cookie(Keyword.get(opts, :cookie_path, "/"))
      |> List.wrap()
      |> Enum.join("; ")

    instance_id = "sync-client-#{System.unique_integer([:positive])}"
    handshake_id = redeem_handshake(base_url, cookie, instance_id)

    params =
      URI.encode_query(
        greeting_params(opts) ++ [handshake_id: handshake_id, instance_id: instance_id]
      )

    stream_url = ~c"#{base_url}/hologram/sse?#{params}"
    headers = [{~c"cookie", ~c"#{cookie}"}]

    {:ok, request_id} =
      :httpc.request(:get, {stream_url, headers}, [], sync: false, stream: :self)

    %__MODULE__{request_id: request_id}
  end

  @doc """
  Returns the sync greeting the given options spell, as query parameters.

  The `:model_hash` and `:protocol_version` default to this build's own, so a client built here
  claims what is true of it. A `:cursor` travels only when given, the same as the browser's
  first visit.
  """
  @spec greeting_params(keyword) :: keyword
  def greeting_params(opts) do
    base = [
      model_hash: Keyword.get(opts, :model_hash, Model.hash()),
      page: Keyword.fetch!(opts, :page),
      protocol_version: Keyword.get(opts, :protocol_version, Frame.protocol_version())
    ]

    case Keyword.get(opts, :cursor) do
      nil -> base
      cursor -> [{:cursor, cursor} | base]
    end
  end

  @doc """
  Returns the next frame of the given SSE event kind, or says that none arrived in time.

  What `await_frame/3` is built on, for the tests that want counting rather than waiting: nothing
  arriving is an answer here rather than a failure, which is how a test says a SECOND frame never
  came.
  """
  @spec next_frame(t, String.t(), non_neg_integer) :: {:ok, map, t} | {:timeout, t}
  def next_frame(client, event_name, timeout_ms \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms

    take_frame(client, event_name, deadline)
  end

  @doc """
  Returns the complete SSE frames the given buffer holds and the partial remainder.

  A frame is the lines up to a blank one, each spelled `name: value` - what arrives over the
  wire in chunks split anywhere, which is why the remainder is kept rather than dropped: the
  next chunk completes it.
  """
  @spec parse_frames(String.t()) :: {list(map), String.t()}
  def parse_frames(buffer) do
    parts = String.split(buffer, "\n\n")
    {complete, [rest]} = Enum.split(parts, -1)

    frames =
      complete
      |> Enum.map(&parse_frame/1)
      |> Enum.reject(&(&1 == %{}))

    {frames, rest}
  end

  defp fetch_session_cookie(base_url, cookie_path) do
    {:ok, {{_version, 200, _reason}, headers, _body}} =
      :httpc.request(:get, {~c"#{base_url}#{cookie_path}", []}, [], [])

    for {~c"set-cookie", value} <- headers do
      value
      |> List.to_string()
      |> String.split(";")
      |> hd()
    end
  end

  defp parse_frame(frame) do
    frame
    |> String.split("\n")
    |> Enum.flat_map(fn line ->
      case String.split(line, ": ", parts: 2) do
        [name, value] -> [{name, value}]
        _not_a_field -> []
      end
    end)
    |> Map.new()
  end

  defp redeem_handshake(base_url, cookie, instance_id) do
    instance_id_hex = Base.encode16(instance_id, case: :lower)

    body =
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

    request = {
      ~c"#{base_url}/hologram/sse/handshake",
      [{~c"cookie", ~c"#{cookie}"}],
      ~c"application/json",
      body
    }

    {:ok, {{_version, 200, _reason}, _headers, response_body}} =
      :httpc.request(:post, request, [], [])

    response_body
    |> List.to_string()
    |> Jason.decode!()
    |> Map.fetch!("handshakeId")
  end

  defp take_frame(%{frames: [frame | rest]} = client, event_name, deadline) do
    if frame["event"] == event_name do
      {:ok, frame, %{client | frames: rest}}
    else
      take_frame(%{client | frames: rest}, event_name, deadline)
    end
  end

  defp take_frame(%{frames: []} = client, event_name, deadline) do
    timeout = deadline - System.monotonic_time(:millisecond)

    if timeout <= 0 do
      {:timeout, client}
    else
      wait_for_frame(client, event_name, deadline, timeout)
    end
  end

  defp wait_for_frame(client, event_name, deadline, timeout) do
    request_id = client.request_id

    receive do
      {:http, {^request_id, :stream_start, _headers}} ->
        take_frame(client, event_name, deadline)

      {:http, {^request_id, :stream, chunk}} ->
        {frames, rest} = parse_frames(client.buffer <> chunk)

        take_frame(%{client | buffer: rest, frames: frames}, event_name, deadline)

      {:http, {^request_id, :stream_end, _headers}} ->
        raise "the stream ended before a #{inspect(event_name)} frame arrived"
    after
      timeout -> {:timeout, client}
    end
  end
end
