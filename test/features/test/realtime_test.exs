defmodule HologramFeatureTests.RealtimeTest do
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.Realtime
  alias Hologram.Realtime.SubscriptionRegistry
  alias HologramFeatureTests.Realtime.Page1
  alias HologramFeatureTests.Realtime.Page2
  alias HologramFeatureTests.Realtime.Page3
  alias HologramFeatureTests.Realtime.Page4
  alias HologramFeatureTests.Realtime.Page5
  alias HologramFeatureTests.Realtime.Page6
  alias HologramFeatureTests.Realtime.Page7
  alias HologramFeatureTests.Realtime.Page8

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

  @sessions 2
  feature "broadcast on application channel fans out to all subscribed sessions", %{
    sessions: [session_1, session_2]
  } do
    session_1 = visit(session_1, Page7)
    session_2 = visit(session_2, Page7)

    click(session_1, button("Broadcast"))

    assert_text(session_1, css("#received"), "delivered")
    assert_text(session_2, css("#received"), "delivered")
  end

  feature "unsubscribe_all drops every cid binding on the channel", %{session: session} do
    session = visit(session, Page8)

    [{instance_id, _entry}] = :ets.tab2list(SubscriptionRegistry.ets_table_name())

    Realtime.unsubscribe_all({:instance, instance_id}, @channel_1)

    session
    |> click(button("Broadcast"))
    |> assert_text(css("#received-page"), "delivered")
    |> assert_text(css("#received-component-1"), "none")
    |> assert_text(css("#received-component-2"), "none")
  end
end
