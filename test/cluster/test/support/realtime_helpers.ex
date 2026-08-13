defmodule HologramClusterTests.RealtimeHelpers do
  @moduledoc """
  Assertion helpers for realtime cluster tests: resolving which peer holds what,
  and gating on cluster-side effects landing before they are asserted.
  """

  import HologramClusterTests.Cluster, only: [rpc: 4]

  alias Hologram.Realtime.SubscriptionRegistry

  # Bounded at 100 x 100ms: the awaited effect lands within a round trip when routing
  # works, so ten seconds without it is a broken premise, not slowness.
  @attempts 100

  @doc """
  Returns the browser session's tab id, read from the browser's own JS context -
  correct no matter which peer serves the tab's requests.
  """
  @spec instance_id_of(Wallaby.Session.t()) :: String.t()
  def instance_id_of(session) do
    {:ok, instance_id} =
      session.driver.execute_script(session, "return globalThis.Hologram.instanceId;")

    instance_id
  end

  @doc """
  Returns the subscription registry entries held by the given peer.
  """
  @spec registry_entries(map) :: list
  def registry_entries(peer) do
    table = rpc(peer, SubscriptionRegistry, :ets_table_name, [])
    rpc(peer, :ets, :tab2list, [table])
  end

  @doc """
  Blocks until some connection on the given peer holds a binding on `channel`,
  or raises once the attempt budget is spent.
  """
  @spec wait_for_channel_binding(map, any) :: :ok
  def wait_for_channel_binding(peer, channel, attempt \\ 1)

  def wait_for_channel_binding(peer, channel, attempt) when attempt > @attempts do
    raise "no binding on #{inspect(channel)} ever appeared on #{inspect(peer.node)}"
  end

  def wait_for_channel_binding(peer, channel, attempt) do
    bound? =
      peer
      |> registry_entries()
      |> Enum.any?(fn {_instance_id, entry} ->
        Enum.any?(entry.bindings, fn {{bound_channel, _cid}, _user_id} ->
          bound_channel == channel
        end)
      end)

    if bound? do
      :ok
    else
      Process.sleep(100)
      wait_for_channel_binding(peer, channel, attempt + 1)
    end
  end

  @doc """
  Blocks until a connection is registered on the given peer, or raises once the
  attempt budget is spent.
  """
  @spec wait_for_connection(map) :: :ok
  def wait_for_connection(peer, attempt \\ 1)

  def wait_for_connection(peer, attempt) when attempt > @attempts do
    raise "no connection ever registered on #{inspect(peer.node)}"
  end

  def wait_for_connection(peer, attempt) do
    if registry_entries(peer) == [] do
      Process.sleep(100)
      wait_for_connection(peer, attempt + 1)
    else
      :ok
    end
  end
end
