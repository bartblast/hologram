defmodule HologramFeatureTests.SSEResponseTest do
  # No browser: the browsers the suite drives accept the header this test refutes, so the
  # response is read with an HTTP client that hands back the headers as the server sent
  # them. Over HTTPS the client negotiates HTTP/2, the protocol where the header is illegal.
  use ExUnit.Case, async: false

  alias Hologram.Realtime.Handshake
  alias Hologram.Runtime.Session
  alias HologramFeatureTestsWeb.Endpoint

  # Generous relative to loopback, where a response either arrives in milliseconds or is
  # never coming.
  @recv_timeout_ms 5_000

  test "the SSE response carries no connection-specific header" do
    {session_id, cookie} = mint_session()
    instance_id = "sse-response-test-instance-id"
    handshake_id = "sse-response-test-handshake-#{:erlang.unique_integer([:positive])}"
    expires_at = System.system_time(:millisecond) + Handshake.stash_ttl_ms()

    Handshake.insert(handshake_id, [], {instance_id, session_id, nil}, expires_at)

    uri = URI.parse(Endpoint.url())
    {scheme, protocol, connect_opts} = connection_for(uri.scheme)

    {:ok, initial_conn} =
      Mint.HTTP.connect(
        scheme,
        uri.host,
        uri.port,
        [mode: :passive, protocols: [protocol]] ++ connect_opts
      )

    assert Mint.HTTP.protocol(initial_conn) == protocol

    request_path = "/hologram/sse?instance_id=#{instance_id}&handshake_id=#{handshake_id}"

    {:ok, requested_conn, request_ref} =
      Mint.HTTP.request(initial_conn, "GET", request_path, [{"cookie", cookie}], nil)

    {final_conn, status, headers} = recv_response_head(requested_conn, request_ref)
    Mint.HTTP.close(final_conn)

    assert status == 200
    assert List.keyfind(headers, "content-type", 0) == {"content-type", "text/event-stream"}
    refute List.keymember?(headers, "connection", 0)
  end

  # Over TLS Bandit offers HTTP/2 and Mint is told to accept nothing else, so a run that
  # somehow negotiated HTTP/1.1 fails at the protocol assertion rather than passing on
  # the wrong protocol. The cert is the self-signed test pair, hence no verification.
  defp connection_for("https") do
    {:https, :http2, [transport_opts: [verify: :verify_none]]}
  end

  defp connection_for("http") do
    {:http, :http1, []}
  end

  # Mints a Hologram session the way a page visit does, by running one page request
  # through the endpoint in-process, and returns the session id with the cookie a client
  # presents to reuse it.
  defp mint_session do
    conn =
      :get
      |> Plug.Test.conn("/realtime/1")
      |> Endpoint.call([])

    %{"phoenix_session" => %{value: cookie_value}} = conn.resp_cookies

    {Session.get_session_id(conn), "phoenix_session=#{cookie_value}"}
  end

  # Reads until the status and headers of the response have both arrived. The stream
  # stays open after that, so the caller closes the connection rather than waiting for
  # a `:done` that never comes.
  defp recv_response_head(conn, request_ref, status \\ nil, headers \\ nil)

  defp recv_response_head(conn, _request_ref, status, headers)
       when status != nil and headers != nil do
    {conn, status, headers}
  end

  defp recv_response_head(conn, request_ref, status, headers) do
    {:ok, new_conn, entries} = Mint.HTTP.recv(conn, 0, @recv_timeout_ms)

    {new_status, new_headers} =
      Enum.reduce(entries, {status, headers}, fn
        {:status, ^request_ref, entry_status}, {_status, acc_headers} ->
          {entry_status, acc_headers}

        {:headers, ^request_ref, entry_headers}, {acc_status, _headers} ->
          {acc_status, entry_headers}

        _entry, acc ->
          acc
      end)

    recv_response_head(new_conn, request_ref, new_status, new_headers)
  end
end
