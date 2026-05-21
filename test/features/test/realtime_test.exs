defmodule HologramFeatureTests.RealtimeTest do
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.Realtime
  alias HologramFeatureTests.Realtime.Page1
  alias HologramFeatureTests.Realtime.Page2
  alias HologramFeatureTests.Realtime.Page3
  alias HologramFeatureTests.Realtime.Page4

  @channel_1 {:room, 1}
  @channel_2 {:room, 2}

  feature "broadcast from outside a Hologram handler", %{session: session} do
    session = visit(session, Page1)

    Realtime.broadcast_action(@channel_1, "page", :show, message: "hello from server")

    assert_text(session, css("#received"), "hello from server")
  end

  feature "delete_subscription stops further broadcasts on that channel",
          %{session: session} do
    session =
      session
      |> visit(Page2)
      |> click(button("Unsubscribe"))
      |> wait_for_no_subscription(@channel_1)

    # Erlang guarantees message order between any two specific processes, so
    # broadcasting on the dropped channel and then on a still-subscribed
    # channel means the second broadcast can only arrive at the SSE process
    # after the first has been processed (or dropped at PubSub if the
    # unsubscribe worked). Waiting for the second broadcast's effect in the
    # DOM is a deterministic barrier that replaces an arbitrary sleep.
    Realtime.broadcast_action(@channel_1, "page", :show_test, message: "delivered")
    Realtime.broadcast_action(@channel_2, "page", :show_sync, message: "ack")

    session
    |> assert_text(css("#received-sync"), "ack")
    |> assert_text(css("#received-test"), "none")
  end

  feature "page subscription is dropped when navigating away to a different page",
          %{session: session} do
    session =
      session
      |> visit(Page3)
      |> click(link("Go to Page 4"))
      |> assert_page(Page4)
      |> click(button("Broadcast"))

    # The command broadcasts on both channels. Channel 2 self-echoes to this
    # client (Page4 is subscribed), so seeing its DOM update is a sync
    # barrier. Channel 1's broadcast finds no subscriber (Page3's binding
    # was dropped on navigation) and produces no self-echo - if the drop
    # didn't actually happen, #received-1 would also update to "delivered".
    session
    |> assert_text(css("#received-2"), "delivered")
    |> assert_text(css("#received-1"), "none")
  end
end
