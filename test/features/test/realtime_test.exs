defmodule HologramFeatureTests.RealtimeTest do
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.Realtime
  alias HologramFeatureTests.Realtime.Page1
  alias HologramFeatureTests.Realtime.Page2

  @sync_channel {:room, 99}
  @test_channel {:room, 42}

  feature "broadcast from outside a Hologram handler", %{session: session} do
    session = visit(session, Page1)

    Realtime.broadcast_action(@test_channel, "page", :show, message: "hello from server")

    assert_text(session, css("#received"), "hello from server")
  end

  feature "delete_subscription stops further broadcasts on that channel",
          %{session: session} do
    session =
      session
      |> visit(Page2)
      |> click(button("Unsubscribe"))
      |> wait_for_no_subscription(@test_channel)

    # Erlang guarantees message order between any two specific processes, so
    # broadcasting on the test channel and then on the sync channel means
    # the sync broadcast can only arrive at the SSE process after the test
    # broadcast has been processed (or dropped at PubSub if the unsubscribe
    # worked). Waiting for the sync broadcast's effect in the DOM is a
    # deterministic barrier that replaces an arbitrary sleep.
    Realtime.broadcast_action(@test_channel, "page", :show_test, message: "delivered")
    Realtime.broadcast_action(@sync_channel, "page", :show_sync, message: "ack")

    session
    |> assert_text(css("#received-sync"), "ack")
    |> assert_text(css("#received-test"), "none")
  end
end
