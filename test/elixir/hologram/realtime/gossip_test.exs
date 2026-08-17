defmodule Hologram.Realtime.GossipTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Realtime.Gossip

  @topic "hologram:gossip:test"

  setup do
    wait_for_process_cleanup(Hologram.PubSub)
    start_supervised!({Phoenix.PubSub, name: Hologram.PubSub})

    :ok
  end

  describe "request_sync/1" do
    # Asking is per connected node, so a single node has nobody to ask. What a peer does
    # with the request, and that it reaches one at all, is covered by the cluster suite -
    # there is no second node here to send to.
    test "asks nobody when no other node is connected" do
      Phoenix.PubSub.subscribe(Hologram.PubSub, @topic)

      assert Node.list() == []
      assert request_sync(@topic) == :ok

      refute_received {:sync_request, _requester_pid}
    end
  end

  describe "request_sync_from/2" do
    test "asks the named node and returns without waiting for a reply" do
      # A single-node test can only target its own node, which is enough to pin the
      # contract: the request carries the caller pid and nothing is waited for.
      Phoenix.PubSub.subscribe(Hologram.PubSub, @topic)

      test_pid = self()

      assert request_sync_from(node(), @topic) == :ok

      assert_receive {:sync_request, ^test_pid}
      refute_received {:sync_reply, _entries}
    end
  end

  describe "reply_to_sync_request/2" do
    test "sends the full table contents back to the requester as a sync reply" do
      table = :ets.new(:gossip_test_table, [:set, :public])
      :ets.insert(table, {:k1, 1})
      :ets.insert(table, {:k2, 2})

      assert reply_to_sync_request(table, self()) == :ok

      assert_received {:sync_reply, entries}
      assert Enum.sort(entries) == [{:k1, 1}, {:k2, 2}]
    end
  end
end
