defmodule Hologram.Realtime.Gossip do
  @moduledoc false

  # Shared gossip wiring for the per-node ETS stores (`Hologram.Realtime.Tombstone` and
  # `Hologram.Realtime.Handshake`): asking peers for what they hold, and answering when
  # they ask. Each store owns its own table, gossip topic, TTL, and merge rule.
  #
  # Nothing here waits. A reply is a message the asking store merges whenever it lands,
  # so a store is never held up by peers that are slow or absent.

  @doc """
  Asks every currently connected node for what it holds, and returns immediately.

  A peer answers by sending a `{:sync_reply, entries}` message, which arrives at the
  caller like any other message. A store that asks this way stays available while its
  peers answer, and merges what arrives in its `handle_info/2` - the same way it merges
  the entries peers gossip to it in steady state. A batch that arrives at boot is only
  a larger batch, not a different kind of event.

  Each node is asked directly rather than through a topic broadcast. A broadcast reaches
  whoever the topic's group membership currently names, and that membership propagates on
  its own schedule - a store asking as its node joins can broadcast into a group that
  does not list its peers yet, and hear nothing back. `Node.list/0` needs only the
  distribution connection, so this asks exactly the nodes that can answer.

  A node with no peers connected asks nobody, which costs it nothing. Peers that connect
  later are picked up by the store's `{:nodeup, node}` handling instead.
  """
  @spec request_sync(String.t()) :: :ok
  def request_sync(gossip_topic) do
    Enum.each(Node.list(), &request_sync_from(&1, gossip_topic))
  end

  @doc """
  Asks one node for what it holds, and returns immediately.

  Used when a node joins, where the newcomer and the node that saw it join are the only
  two that can hold state the other is missing. Asking the whole topic instead would
  have every node dump its entire table to every other node on every join, which grows
  quadratically with the cluster for state all but one of them already has.
  """
  @spec request_sync_from(node, String.t()) :: :ok
  def request_sync_from(node, gossip_topic) do
    Phoenix.PubSub.direct_broadcast(
      node,
      Hologram.PubSub,
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
end
