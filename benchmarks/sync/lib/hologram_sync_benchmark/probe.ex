defmodule HologramSyncBenchmark.Probe do
  @moduledoc false

  # Stands in for the app's own users while a case runs: requests a page on a fixed schedule and
  # records how long each took, so a case can show whether sync's work slows the app down.
  #
  # Each request is timed from when it was due rather than from when it was sent. Sent one at a
  # time, a stalled request holds back the ones behind it, and timing those from their send would
  # hide the stall from every request but the first.
  #
  # One kept-alive connection, so the probe doesn't compete with a wave of clients for the listen
  # backlog. High priority, since it shares the driver's VM with thousands of client processes,
  # whose work would otherwise count as the server being slow.

  alias HologramSyncBenchmark.Measure

  @interval_ms 50

  @path "/probe"

  @timeout_ms 10_000

  @type sample :: {integer, float | :failed}

  @type summary :: %{
          failures: non_neg_integer,
          max_ms: float | nil,
          p50_ms: float | nil,
          p95_ms: float | nil,
          p99_ms: float | nil,
          requests: non_neg_integer
        }

  @doc """
  Starts requesting the probe page of the server at the given base URL, 20 times a second, and
  returns the probe. Linked to the caller, so it goes if the caller crashes. A caller that carries
  on after a failure has to stop it, with `stop/1`.
  """
  @spec start(String.t()) :: pid
  def start(base_url) do
    uri = URI.parse(base_url)

    spawn_link(fn ->
      Process.flag(:priority, :high)

      loop(%{
        conn: nil,
        due_at: now_ms(),
        host: uri.host,
        port: uri.port,
        samples: []
      })
    end)
  end

  @doc """
  Stops the given probe and returns its samples, each the monotonic millisecond the request was
  due at with how many milliseconds it took from then, or `:failed`. A request that was due but
  never sent, since the ones ahead of it ran late, counts with how long it had waited by the stop,
  which is the least it would have taken.

  Waits for a request under way, so it can take as long as a request's timeout.
  """
  @spec stop(pid) :: [sample]
  def stop(probe) do
    ref = Process.monitor(probe)
    send(probe, {:stop, self(), ref})

    receive do
      {^ref, samples} ->
        Process.demonitor(ref, [:flush])
        samples

      {:DOWN, ^ref, :process, ^probe, reason} ->
        raise "the probe went down: #{inspect(reason)}"
    end
  end

  @doc """
  Returns the figures of the given samples that were due from the first given monotonic millisecond
  up to but not including the second.
  """
  @spec summary([sample], integer, integer) :: summary
  def summary(samples, from_ms, to_ms) do
    in_range =
      Enum.filter(samples, fn {due_at, _taken} -> due_at >= from_ms and due_at < to_ms end)

    times = for {_due_at, taken} <- in_range, taken != :failed, do: taken

    %{
      failures: length(in_range) - length(times),
      max_ms: Enum.max(times, fn -> nil end),
      p50_ms: Measure.percentile(times, 50),
      p95_ms: Measure.percentile(times, 95),
      p99_ms: Measure.percentile(times, 99),
      requests: length(in_range)
    }
  end

  # Waits for the next request's turn, or goes straight on when the last one ran past it.
  defp loop(state) do
    wait_ms = max(state.due_at - now_ms(), 0)

    receive do
      {:stop, from, ref} ->
        if state.conn, do: Mint.HTTP.close(state.conn)
        send(from, {ref, Enum.reverse(state.samples) ++ unsent(state.due_at, now_ms())})
    after
      wait_ms ->
        state
        |> request()
        |> Map.update!(:due_at, &(&1 + @interval_ms))
        |> loop()
    end
  end

  defp unsent(due_at, now) when due_at >= now, do: []

  defp unsent(due_at, now) do
    [{due_at, (now - due_at) * 1.0} | unsent(due_at + @interval_ms, now)]
  end

  defp request(state) do
    deadline = now_ms() + @timeout_ms

    with {:ok, conn} <- open(state),
         {:ok, conn, ref} <- send_request(conn),
         {:ok, conn} <- await_response(conn, ref, nil, deadline) do
      taken = (System.monotonic_time(:microsecond) - state.due_at * 1_000) / 1_000

      %{state | conn: conn, samples: [{state.due_at, taken} | state.samples]}
    else
      {:error, conn} ->
        if conn, do: Mint.HTTP.close(conn)

        %{state | conn: nil, samples: [{state.due_at, :failed} | state.samples]}
    end
  end

  # The server keeps a connection open between requests, with no limit on how many it serves and
  # this one never idle for long, so one it does close counts as a failed request.
  defp open(%{conn: conn} = state) when conn != nil do
    if Mint.HTTP.open?(conn) do
      {:ok, conn}
    else
      Mint.HTTP.close(conn)
      open(%{state | conn: nil})
    end
  end

  defp open(state) do
    case Mint.HTTP.connect(:http, state.host, state.port,
           mode: :passive,
           transport_opts: [timeout: @timeout_ms]
         ) do
      {:ok, conn} -> {:ok, conn}
      {:error, _reason} -> {:error, nil}
    end
  end

  defp send_request(conn) do
    case Mint.HTTP.request(conn, "GET", @path, [], nil) do
      {:ok, conn, ref} -> {:ok, conn, ref}
      {:error, conn, _reason} -> {:error, conn}
    end
  end

  defp await_response(conn, ref, status, deadline) do
    case Mint.HTTP.recv(conn, 0, max(deadline - now_ms(), 0)) do
      {:ok, conn, responses} ->
        status = Enum.find_value(responses, status, &response_status(&1, ref))

        cond do
          not Enum.member?(responses, {:done, ref}) -> await_response(conn, ref, status, deadline)
          status == 200 -> {:ok, conn}
          true -> {:error, conn}
        end

      {:error, conn, _reason, _responses} ->
        {:error, conn}
    end
  end

  defp response_status({:status, ref, status}, ref), do: status

  defp response_status(_response, _ref), do: nil

  defp now_ms, do: System.monotonic_time(:millisecond)
end
