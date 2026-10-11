defmodule HologramCowboyTests.Helpers do
  alias Hologram.Realtime
  alias Hologram.Realtime.SubscriptionRegistry

  @max_wait_time Application.compile_env(:wallaby, :max_wait_time, 3_000)

  @doc """
  Blocks until at least `count` (default 1) `SubscriptionRegistry` connections
  hold a binding on `channel`, then returns the `session` so the helper can be
  piped. Raises if the count is not reached within `@max_wait_time`.

  Gate any broadcast whose recipients a test asserts on: subscriptions register
  asynchronously after the page mounts (handshake POST + SSE attach), and
  `Phoenix.PubSub` is fire-and-forget, so a broadcast that fires first reaches
  no one. Pass `count` > 1 to require every participating connection in a
  multi-session test.

  A connection counts once its SSE process can receive broadcasts on `channel`,
  not merely once the registry records the binding.
  """
  def wait_for_subscription(session, channel, count \\ 1, start_time \\ nil) do
    start_time = start_time || current_time()

    cond do
      subscription_count(channel) >= count ->
        session

      timed_out?(start_time) ->
        raise Wallaby.ExpectationNotMetError,
              "Timed out waiting for #{count} subscription(s) on #{inspect(channel)}"

      true ->
        :timer.sleep(100)
        wait_for_subscription(session, channel, count, start_time)
    end
  end

  defp current_time do
    :erlang.monotonic_time(:milli_seconds)
  end

  # Whether the connection holds a binding on the channel and its SSE process has
  # subscribed to the channel's PubSub topic. The registry records a binding before
  # the SSE process subscribes, which it does only when it handles the
  # `{:sub, channel}` message the registry sends it, and a broadcast in between
  # reaches no one.
  defp receiving?(entry, channel) do
    Enum.any?(entry.bindings, fn {{ch, _cid}, _user_id} -> ch == channel end) and
      Realtime.channel_topic(channel) in Registry.keys(Hologram.PubSub, entry.sse_pid)
  end

  defp subscription_count(channel) do
    SubscriptionRegistry.ets_table_name()
    |> :ets.tab2list()
    |> Enum.count(fn {_instance_id, entry} -> receiving?(entry, channel) end)
  end

  defp timed_out?(start_time) do
    current_time() - start_time > @max_wait_time
  end
end
