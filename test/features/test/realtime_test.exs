defmodule HologramFeatureTests.RealtimeTest do
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.Realtime
  alias HologramFeatureTests.Realtime.Page1
  alias HologramFeatureTests.Realtime.Page2
  alias HologramFeatureTests.Realtime.Page3
  alias HologramFeatureTests.Realtime.Page4
  alias HologramFeatureTests.Realtime.Page5
  alias HologramFeatureTests.Realtime.Page6

  @channel_1 {:room, 1}

  feature "broadcast from outside a Hologram handler", %{session: session} do
    session = visit(session, Page1)

    Realtime.broadcast_action(@channel_1, "page", :show, message: "delivered")

    assert_text(session, css("#received"), "delivered")
  end

  feature "delete_subscription stops further broadcasts on that channel", %{session: session} do
    session
    |> visit(Page2)
    |> click(button("Unsubscribe and broadcast"))
    |> assert_text(css("#received-2"), "delivered")
    |> assert_text(css("#received-1"), "none")
  end

  feature "page subscription is dropped when navigating away to a different page", %{
    session: session
  } do
    session
    |> visit(Page3)
    |> click(link("Go to Page 4"))
    |> assert_page(Page4)
    |> click(button("Broadcast"))
    |> assert_text(css("#received-2"), "delivered")
    |> assert_text(css("#received-1"), "none")
  end

  feature "shared layout subscription persists across page navigation", %{session: session} do
    session
    |> visit(Page5)
    |> click(link("Go to Page 6"))
    |> assert_page(Page6)
    |> click(button("Broadcast"))
    |> assert_text(css("#received-shared"), "delivered")
  end
end
