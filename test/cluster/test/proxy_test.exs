defmodule HologramClusterTests.ProxyTest do
  use ExUnit.Case, async: false

  import HologramClusterTests.Proxy

  alias HologramClusterTests.HTTPClient
  alias HologramClusterTests.Proxy

  defmodule StubUpstream do
    @moduledoc false

    @behaviour Plug

    @impl Plug
    def init(port), do: port

    @impl Plug
    def call(conn, port) do
      case conn.request_path do
        "/echo-cookie" ->
          cookie_header =
            conn.req_headers
            |> Enum.filter(fn {name, _value} -> name == "cookie" end)
            |> Enum.map_join(";", fn {_name, value} -> value end)

          Plug.Conn.send_resp(conn, 200, cookie_header)

        "/set-cookies" ->
          conn
          |> Plug.Conn.put_resp_cookie("stub_cookie_a", "1")
          |> Plug.Conn.put_resp_cookie("stub_cookie_b", "2")
          |> Plug.Conn.send_resp(200, "ok")

        "/stream" ->
          conn = Plug.Conn.send_chunked(conn, 200)
          {:ok, conn} = Plug.Conn.chunk(conn, "chunk-1\n")

          Process.sleep(300)
          {:ok, conn} = Plug.Conn.chunk(conn, "chunk-2\n")

          Process.sleep(300)
          {:ok, conn} = Plug.Conn.chunk(conn, "chunk-3\n")

          conn

        _other ->
          Plug.Conn.send_resp(conn, 200, "upstream:#{port}")
      end
    end
  end

  @stub_port_1 4021
  @stub_port_2 4022

  setup_all do
    for port <- [@stub_port_1, @stub_port_2] do
      # Stub listener names form a bounded set (one per stub port), so runtime atom
      # creation is safe here.
      # credo:disable-for-next-line Credo.Check.Warning.UnsafeToAtom
      ref = :"stub_upstream_#{port}"
      {:ok, _pid} = Plug.Cowboy.http(StubUpstream, port, port: port, ref: ref)
      on_exit(fn -> Plug.Cowboy.shutdown(ref) end)
    end

    start_supervised!({Proxy, upstreams: [@stub_port_1, @stub_port_2]})

    :ok
  end

  # What a fresh proxy gave each test, given back without a rebind: an empty log and the
  # full upstream set. Policies and the round-robin counter carry over, and nothing here
  # reads either - a policy is selected by the token its own test minted, and the one
  # alternation test asserts the SET of two upstreams, not which came first.
  setup do
    clear_log()
    put_upstreams([@stub_port_1, @stub_port_2])

    :ok
  end

  defp get_through_proxy(path, request_headers \\ []) do
    proxy_port = Application.fetch_env!(:hologram_cluster_tests, :proxy_port)

    HTTPClient.get("http://127.0.0.1:#{proxy_port}#{path}", request_headers)
  end

  defp served_by(response) do
    {"x-upstream", upstream} = List.keyfind(response.headers, "x-upstream", 0)
    String.to_integer(upstream)
  end

  describe "clear_log/0" do
    test "empties the request log" do
      get_through_proxy("/")
      clear_log()

      assert log() == []
    end
  end

  describe "log/0" do
    test "records method, path and serving upstream for each request, in order" do
      first_upstream = served_by(get_through_proxy("/"))
      second_upstream = served_by(get_through_proxy("/echo-cookie"))

      assert log() == [
               %{method: "GET", path: "/", upstream: first_upstream},
               %{method: "GET", path: "/echo-cookie", upstream: second_upstream}
             ]
    end
  end

  describe "put_upstreams/1" do
    test "replaces the upstream set for subsequent routing" do
      put_upstreams([@stub_port_2])

      assert served_by(get_through_proxy("/")) == @stub_port_2
      assert served_by(get_through_proxy("/")) == @stub_port_2
    end
  end

  describe "register_policy/1" do
    test "routes requests carrying the token cookie through the registered policy" do
      token =
        register_policy(fn _request_facts, %{upstreams: upstreams} -> List.last(upstreams) end)

      request_headers = [{"cookie", "#{route_cookie()}=#{token}"}]

      assert served_by(get_through_proxy("/", request_headers)) == @stub_port_2
      assert served_by(get_through_proxy("/", request_headers)) == @stub_port_2
      assert served_by(get_through_proxy("/", request_headers)) == @stub_port_2
    end

    test "hands the policy the request facts" do
      token =
        register_policy(fn %{method: "GET", path: "/echo-cookie"},
                           %{upstreams: [first | _rest]} ->
          first
        end)

      request_headers = [{"cookie", "#{route_cookie()}=#{token}"}]

      assert served_by(get_through_proxy("/echo-cookie", request_headers)) == @stub_port_1
    end
  end

  describe "request forwarding" do
    test "alternates upstreams for consecutive requests when no policy cookie is set" do
      first_upstream = served_by(get_through_proxy("/"))
      second_upstream = served_by(get_through_proxy("/"))

      assert Enum.sort([first_upstream, second_upstream]) == [@stub_port_1, @stub_port_2]
    end

    test "stamps the response with the upstream that served it" do
      response = get_through_proxy("/")

      assert response.body == "upstream:#{served_by(response)}"
    end

    test "forwards request cookies to the upstream" do
      response = get_through_proxy("/echo-cookie", [{"cookie", "stub=42"}])

      assert response.body == "stub=42"
    end

    test "relays every set-cookie header rather than collapsing them" do
      response = get_through_proxy("/set-cookies")

      set_cookie_headers =
        Enum.filter(response.headers, fn {name, _value} ->
          String.downcase(name) == "set-cookie"
        end)

      assert length(set_cookie_headers) == 2
    end

    test "streams response chunks as the upstream produces them" do
      proxy_port = Application.fetch_env!(:hologram_cluster_tests, :proxy_port)

      chunk_times = HTTPClient.chunk_times("http://127.0.0.1:#{proxy_port}/stream")

      # The upstream sends three chunks, sleeping 300ms between them. Asserted first, so
      # a missing chunk reads as a missing chunk rather than as a short spread.
      assert length(chunk_times) == 3

      # A buffering proxy would deliver all three in one burst at the end - the spread
      # proves each was relayed as it was produced.
      assert List.last(chunk_times) - List.first(chunk_times) >= 400
    end
  end
end
