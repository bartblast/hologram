defmodule HologramClusterTests.Proxy do
  @moduledoc """
  The streaming reverse proxy that is the browser's only origin.

  Every browser request lands here and is forwarded to one of the registered
  upstreams (ports on loopback). Which one is the routing policy's decision:
  round-robin by default, or a per-browser policy registered with
  `register_policy/1` and selected by a cookie the test sets on its own
  browser. Response chunks are relayed as the upstream produces them, so
  long-lived streams flow through without buffering.

  Every response is stamped with an `x-upstream` header and every request is
  appended to a log tests can query, so a test asserts which upstream actually
  served a request rather than assuming the policy worked.
  """

  use GenServer

  @cowboy_ref :hologram_cluster_tests_proxy

  @log_table :hologram_cluster_tests_proxy_log

  @route_cookie "hologram_cluster_tests_route"

  @state_table :hologram_cluster_tests_proxy_state

  @doc false
  @spec choose_upstream(%{method: String.t(), path: String.t(), cookies: map}) :: pos_integer
  def choose_upstream(request_facts) do
    current_upstreams = upstreams()

    case :ets.lookup(@state_table, {:policy, request_facts.cookies[@route_cookie]}) do
      [{{:policy, _token}, policy}] ->
        policy.(request_facts, %{upstreams: current_upstreams})

      [] ->
        round_robin(current_upstreams)
    end
  end

  @doc """
  Empties the request log.
  """
  @spec clear_log() :: :ok
  def clear_log do
    :ets.delete_all_objects(@log_table)
    :ok
  end

  @doc """
  Returns the proxied requests in the order they were routed, each as a map
  with `:method`, `:path` and `:upstream`.
  """
  @spec log() :: [%{method: String.t(), path: String.t(), upstream: pos_integer}]
  def log do
    @log_table
    |> :ets.tab2list()
    |> Enum.sort_by(fn {key, _entry} -> key end)
    |> Enum.map(fn {_key, entry} -> entry end)
  end

  @doc false
  @spec log_request(String.t(), String.t(), pos_integer) :: :ok
  def log_request(method, path, upstream) do
    key = :erlang.unique_integer([:monotonic, :positive])
    entry = %{method: method, path: path, upstream: upstream}

    :ets.insert(@log_table, {key, entry})
    :ok
  end

  @doc """
  Replaces the upstream set used for subsequent routing decisions.
  """
  @spec put_upstreams([pos_integer]) :: :ok
  def put_upstreams(upstreams) do
    :ets.insert(@state_table, {:upstreams, upstreams})
    :ok
  end

  @doc """
  Stores `policy` and returns the token that selects it: a browser carrying the
  token as the `route_cookie/0` cookie has its requests routed by this policy
  instead of the round-robin default.

  The policy receives the request facts and the cluster facts, and returns the
  upstream to forward to:

      fn %{method: _, path: path, cookies: _}, %{upstreams: [a, b]} ->
        if String.starts_with?(path, "/hologram/sse"), do: a, else: b
      end
  """
  @spec register_policy((%{method: String.t(), path: String.t(), cookies: map},
                         %{upstreams: [pos_integer]} ->
                           pos_integer)) :: String.t()
  def register_policy(policy) do
    token = "policy-#{:erlang.unique_integer([:positive])}"

    :ets.insert(@state_table, {{:policy, token}, policy})
    token
  end

  @doc """
  Returns the name of the cookie whose value selects a registered routing
  policy for the browser carrying it.
  """
  @spec route_cookie() :: String.t()
  def route_cookie, do: @route_cookie

  @doc """
  Starts the proxy: its state tables and the HTTP listener on the configured
  proxy port. `opts` must include `:upstreams`, the initial upstream port list.
  """
  @spec start_link(keyword) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the current upstream port list.
  """
  @spec upstreams() :: [pos_integer]
  def upstreams do
    [{:upstreams, upstreams}] = :ets.lookup(@state_table, :upstreams)
    upstreams
  end

  @impl GenServer
  def init(opts) do
    # Without trapping exits a supervisor shutdown skips terminate/2, and the HTTP
    # listener would outlive this server and collide with the next start.
    Process.flag(:trap_exit, true)

    :ets.new(@log_table, [:set, :public, :named_table])
    :ets.new(@state_table, [:set, :public, :named_table])

    :ets.insert(@state_table, {:rr_counter, 0})
    put_upstreams(Keyword.fetch!(opts, :upstreams))

    proxy_port = Application.fetch_env!(:hologram_cluster_tests, :proxy_port)

    {:ok, _cowboy_pid} =
      Plug.Cowboy.http(HologramClusterTests.Proxy.Forwarder, [],
        port: proxy_port,
        ref: @cowboy_ref
      )

    {:ok, %{}}
  end

  @impl GenServer
  def terminate(_reason, _state) do
    Plug.Cowboy.shutdown(@cowboy_ref)
  end

  defp round_robin(upstreams) do
    index = :ets.update_counter(@state_table, :rr_counter, 1)

    Enum.at(upstreams, rem(index, length(upstreams)))
  end
end

defmodule HologramClusterTests.Proxy.Forwarder do
  @moduledoc false

  @behaviour Plug

  alias HologramClusterTests.Proxy

  # Covers the longest legitimate silence on a proxied stream: SSE heartbeats arrive
  # every 15s, so a minute of nothing means the upstream is gone, not idle.
  @recv_timeout_ms 60_000

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(initial_conn, _opts) do
    conn = Plug.Conn.fetch_cookies(initial_conn)

    request_facts = %{
      method: conn.method,
      path: conn.request_path,
      cookies: conn.req_cookies
    }

    upstream = Proxy.choose_upstream(request_facts)
    Proxy.log_request(conn.method, conn.request_path, upstream)

    forward(conn, upstream)
  end

  defp build_request_path(conn) do
    case conn.query_string do
      "" -> conn.request_path
      query_string -> "#{conn.request_path}?#{query_string}"
    end
  end

  # The host header names this proxy, so it is rewritten for the upstream. Everything
  # else - cookies included - passes through untouched, in both directions.
  defp build_request_headers(conn, upstream) do
    forwarded_headers = Enum.reject(conn.req_headers, fn {name, _value} -> name == "host" end)

    [{"host", "127.0.0.1:#{upstream}"} | forwarded_headers]
  end

  defp forward(conn, upstream) do
    {:ok, request_body, conn} = read_full_body(conn, [])

    {:ok, initial_mint_conn} = Mint.HTTP.connect(:http, "127.0.0.1", upstream, mode: :passive)

    request_path = build_request_path(conn)
    request_headers = build_request_headers(conn, upstream)

    {:ok, mint_conn, request_ref} =
      Mint.HTTP.request(
        initial_mint_conn,
        conn.method,
        request_path,
        request_headers,
        request_body
      )

    relay_response(conn, mint_conn, request_ref, upstream, %{headers: [], status: nil})
  end

  defp read_full_body(conn, acc) do
    case Plug.Conn.read_body(conn) do
      {:ok, part, conn} ->
        body =
          [part | acc]
          |> Enum.reverse()
          |> IO.iodata_to_binary()

        {:ok, body, conn}

      {:more, part, conn} ->
        read_full_body(conn, [part | acc])
    end
  end

  # Streams the upstream's response to the browser as it arrives. The response is opened
  # towards the browser on the first data entry (or on :done for bodiless responses), and
  # every subsequent data entry is relayed as its own chunk - never accumulated.
  defp relay_response(conn, mint_conn, request_ref, upstream, response) do
    case Mint.HTTP.recv(mint_conn, 0, @recv_timeout_ms) do
      {:ok, mint_conn, entries} ->
        case relay_entries(conn, entries, request_ref, upstream, response) do
          {:cont, conn, response} ->
            relay_response(conn, mint_conn, request_ref, upstream, response)

          {:halt, conn} ->
            Mint.HTTP.close(mint_conn)
            conn
        end

      {:error, _mint_conn, _reason, _entries} ->
        halt_towards_browser(conn, upstream, response)
    end
  end

  defp relay_entries(conn, [], _request_ref, _upstream, response), do: {:cont, conn, response}

  defp relay_entries(conn, [entry | rest], request_ref, upstream, response) do
    case relay_entry(conn, entry, request_ref, upstream, response) do
      {:cont, conn, response} -> relay_entries(conn, rest, request_ref, upstream, response)
      {:halt, conn} -> {:halt, conn}
    end
  end

  defp relay_entry(conn, {:status, request_ref, status}, request_ref, _upstream, response) do
    {:cont, conn, %{response | status: status}}
  end

  defp relay_entry(conn, {:headers, request_ref, headers}, request_ref, _upstream, response) do
    {:cont, conn, %{response | headers: response.headers ++ headers}}
  end

  defp relay_entry(conn, {:data, request_ref, data}, request_ref, upstream, response) do
    conn = open_towards_browser(conn, upstream, response)

    case Plug.Conn.chunk(conn, data) do
      {:ok, conn} -> {:cont, conn, response}
      {:error, _reason} -> {:halt, conn}
    end
  end

  defp relay_entry(conn, {:done, request_ref}, request_ref, upstream, response) do
    if conn.state == :chunked do
      {:halt, conn}
    else
      # No body at all - answer without entering chunked encoding.
      conn =
        conn
        |> put_response_headers(upstream, response)
        |> Plug.Conn.send_resp(response.status, "")

      {:halt, conn}
    end
  end

  defp halt_towards_browser(conn, upstream, response) do
    if conn.state == :chunked do
      conn
    else
      conn
      |> put_response_headers(upstream, %{response | status: 502, headers: []})
      |> Plug.Conn.send_resp(502, "upstream did not respond")
    end
  end

  defp open_towards_browser(%Plug.Conn{state: :chunked} = conn, _upstream, _response), do: conn

  defp open_towards_browser(conn, upstream, response) do
    conn
    |> put_response_headers(upstream, response)
    |> Plug.Conn.send_chunked(response.status)
  end

  # Hop-by-hop headers describe the upstream connection, not the one to the browser -
  # Plug manages those on its own side. Prepended rather than put one by one, since put
  # replaces same-named headers and would collapse multiple set-cookie headers into one.
  defp put_response_headers(conn, upstream, response) do
    forwarded_headers =
      Enum.reject(response.headers, fn {name, _value} ->
        name in ["connection", "content-length", "transfer-encoding"]
      end)

    conn
    |> Plug.Conn.prepend_resp_headers(forwarded_headers)
    |> Plug.Conn.put_resp_header("x-upstream", Integer.to_string(upstream))
  end
end
