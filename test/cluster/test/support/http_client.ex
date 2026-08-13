defmodule HologramClusterTests.HTTPClient do
  @moduledoc """
  The HTTP client cluster tests make their assertions with.

  Requests are issued with Mint in passive mode, the same client the proxy
  relays with, so this app has one model of HTTP throughout. Responses are
  returned whole, with headers in arrival order and duplicates preserved - a
  test asserting on repeated `set-cookie` headers needs them intact.

  Every failure raises: a test client that cannot reach its target is a broken
  premise, not a result to assert on.
  """

  # Generous relative to loopback, where a response either arrives in
  # milliseconds or is never coming.
  @recv_timeout_ms 5_000

  @doc """
  Sends a GET and returns the monotonic millisecond timestamp of each response
  chunk, in arrival order.

  Each timestamp is taken as the chunk leaves the socket, so the spread across
  the returned list is the spread the server produced, plus loopback.
  """
  @spec chunk_times(String.t(), [{String.t(), String.t()}]) :: [integer]
  def chunk_times(url, request_headers \\ []) do
    {conn, request_ref} = send_request(url, request_headers)

    recv_chunk_times(conn, request_ref, [])
  end

  @doc """
  Sends a GET and returns the response as a map with `:body`, `:headers` and
  `:status`.
  """
  @spec get(String.t(), [{String.t(), String.t()}]) :: %{
          body: String.t(),
          headers: [{String.t(), String.t()}],
          status: pos_integer
        }
  def get(url, request_headers \\ []) do
    {conn, request_ref} = send_request(url, request_headers)

    recv_response(conn, request_ref, %{body: [], headers: [], status: nil})
  end

  defp recv_chunk_times(conn, request_ref, chunk_times) do
    case Mint.HTTP.recv(conn, 0, @recv_timeout_ms) do
      {:ok, new_conn, entries} ->
        new_chunk_times = stamp_data_entries(entries, request_ref, chunk_times)

        if Enum.any?(entries, &match?({:done, ^request_ref}, &1)) do
          Mint.HTTP.close(new_conn)
          Enum.reverse(new_chunk_times)
        else
          recv_chunk_times(new_conn, request_ref, new_chunk_times)
        end

      # A server that closes mid-stream ends the list rather than failing: whatever was
      # measured is the measurement. The error carries the entries parsed before it, so
      # they are stamped too - dropping them would lose the last chunks the server did
      # manage to send.
      {:error, _conn, _reason, entries} ->
        entries
        |> stamp_data_entries(request_ref, chunk_times)
        |> Enum.reverse()
    end
  end

  defp recv_response(conn, request_ref, response) do
    {:ok, new_conn, entries} = Mint.HTTP.recv(conn, 0, @recv_timeout_ms)

    new_response = Enum.reduce(entries, response, &reduce_entry(&1, request_ref, &2))

    if Enum.any?(entries, &match?({:done, ^request_ref}, &1)) do
      Mint.HTTP.close(new_conn)

      %{new_response | body: IO.iodata_to_binary(new_response.body)}
    else
      recv_response(new_conn, request_ref, new_response)
    end
  end

  defp reduce_entry({:data, request_ref, data}, request_ref, response) do
    %{response | body: [response.body, data]}
  end

  defp reduce_entry({:headers, request_ref, headers}, request_ref, response) do
    %{response | headers: response.headers ++ headers}
  end

  defp reduce_entry({:status, request_ref, status}, request_ref, response) do
    %{response | status: status}
  end

  defp reduce_entry(_entry, _request_ref, response), do: response

  defp request_path(%URI{path: path, query: nil}), do: path || "/"

  defp request_path(%URI{path: path, query: query}), do: "#{path || "/"}?#{query}"

  defp send_request(url, request_headers) do
    uri = URI.parse(url)

    {:ok, conn} = Mint.HTTP.connect(:http, uri.host, uri.port, mode: :passive)

    {:ok, new_conn, request_ref} =
      Mint.HTTP.request(conn, "GET", request_path(uri), request_headers, nil)

    {new_conn, request_ref}
  end

  # One timestamp per recv batch: entries that arrived together did arrive together, and
  # claiming otherwise would invent precision the socket read cannot give.
  defp stamp_data_entries(entries, request_ref, chunk_times) do
    now = System.monotonic_time(:millisecond)

    Enum.reduce(entries, chunk_times, fn
      {:data, ^request_ref, _data}, acc -> [now | acc]
      _entry, acc -> acc
    end)
  end
end
