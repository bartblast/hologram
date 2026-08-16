defmodule Hologram.Realtime.Gossip do
  @moduledoc false

  # Shared boot-sync mechanics for the per-node, gossiped ETS stores
  # (`Hologram.Realtime.Tombstone` and `Hologram.Realtime.Handshake`). Each
  # store owns its own table, gossip topic, TTL, and per-entry merge rule; the
  # request/collect/reply wiring is identical and lives here.

  @doc """
  Broadcasts a sync request to peers on `gossip_topic`, then blocks up to
  `timeout_ms` collecting `{:sync_reply, entries}` responses, invoking
  `merge_fun` on each batch. Returns `:ok` once the window elapses.

  Run this inside a `handle_continue/2` so a freshly booted node catches up on
  peer state without blocking `init/1` (and thus the supervision tree) for the
  full timeout.
  """
  # TODO: Remove once neither store waits for its peers - request_sync/1 replaces it.
  @spec boot_sync(String.t(), non_neg_integer, ([term] -> any)) :: :ok
  def boot_sync(gossip_topic, timeout_ms, merge_fun) do
    Phoenix.PubSub.broadcast_from(
      Hologram.PubSub,
      self(),
      gossip_topic,
      {:sync_request, self()}
    )

    collect_sync_replies(System.monotonic_time(:millisecond) + timeout_ms, merge_fun)
  end

  @doc """
  Asks the peers on `gossip_topic` for what they hold, and returns immediately.

  A peer answers by sending a `{:sync_reply, entries}` message, which arrives at the
  caller like any other message. A store that asks this way stays available while its
  peers answer, and merges what arrives in its `handle_info/2` - the same way it merges
  the entries peers gossip to it in steady state. A batch that arrives at boot is only
  a larger batch, not a different kind of event.

  A node with no peers hears nothing back, which costs it nothing.
  """
  @spec request_sync(String.t()) :: :ok
  def request_sync(gossip_topic) do
    Phoenix.PubSub.broadcast_from(
      Hologram.PubSub,
      self(),
      gossip_topic,
      {:sync_request, self()}
    )
  end

  @doc """
  Replies to a peer's `{:sync_request, requester_pid}` by sending the full
  contents of `table_name` back as a `{:sync_reply, entries}` message.
  """
  @spec reply_to_sync_request(atom, pid) :: :ok
  def reply_to_sync_request(table_name, requester_pid) do
    send(requester_pid, {:sync_reply, :ets.tab2list(table_name)})

    :ok
  end

  defp collect_sync_replies(deadline, merge_fun) do
    remaining_ms = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {:sync_reply, entries} ->
        merge_fun.(entries)
        collect_sync_replies(deadline, merge_fun)
    after
      remaining_ms -> :ok
    end
  end
end
