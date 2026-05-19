defmodule Hologram.Realtime.HandshakeTest do
  use Hologram.Test.BasicCase, async: false

  import Hologram.Realtime.Handshake

  alias Hologram.Realtime.Handshake

  setup do
    wait_for_process_cleanup(Handshake)
    start_supervised!(Handshake)

    :ok
  end

  describe "insert/4" do
    test "stashes the handshake entry in ETS with the identity tuple flattened" do
      insert(
        "test-handshake-id",
        [{{:room_a, "page"}, "test-user-id"}],
        {"test-instance-id", "test-session-id", "test-user-id"},
        1_700_000_000_000
      )

      assert :ets.lookup(ets_table_name(), "test-handshake-id") == [
               {
                 "test-handshake-id",
                 [{{:room_a, "page"}, "test-user-id"}],
                 "test-instance-id",
                 "test-session-id",
                 "test-user-id",
                 1_700_000_000_000
               }
             ]
    end
  end
end
