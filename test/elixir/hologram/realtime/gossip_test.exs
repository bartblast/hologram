defmodule Hologram.Realtime.GossipTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Realtime.Gossip

  @topic "hologram:gossip:test"

  setup do
    wait_for_process_cleanup(Hologram.PubSub)
    start_supervised!({Phoenix.PubSub, name: Hologram.PubSub})

    :ok
  end

  describe "boot_sync/3" do
    test "broadcasts a sync request carrying the caller pid to peers on the topic" do
      test_pid = self()

      spawn_link(fn ->
        Phoenix.PubSub.subscribe(Hologram.PubSub, @topic)
        send(test_pid, :peer_ready)

        receive do
          {:sync_request, requester_pid} -> send(test_pid, {:got_request, requester_pid})
        end
      end)

      assert_receive :peer_ready

      boot_sync(@topic, 20, fn _entries -> :ok end)

      assert_received {:got_request, ^test_pid}
    end

    test "invokes merge_fun for each sync reply received within the window" do
      test_pid = self()

      send(self(), {:sync_reply, [{:a, 1}]})
      send(self(), {:sync_reply, [{:b, 2}]})

      boot_sync(@topic, 20, fn entries -> send(test_pid, {:merged, entries}) end)

      assert_received {:merged, [{:a, 1}]}
      assert_received {:merged, [{:b, 2}]}
    end

    test "returns :ok after the timeout when no replies arrive" do
      assert boot_sync(@topic, 10, fn _entries -> flunk("merge_fun should not run") end) == :ok
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
