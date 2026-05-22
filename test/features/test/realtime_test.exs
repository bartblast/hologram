# credo:disable-for-this-file Credo.Check.Refactor.VariableRebinding
defmodule HologramFeatureTests.RealtimeTest do
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.Realtime
  alias HologramFeatureTests.Realtime.Page1
  alias HologramFeatureTests.Realtime.Page2
  alias HologramFeatureTests.Realtime.Page3
  alias HologramFeatureTests.Realtime.Page4
  alias HologramFeatureTests.Realtime.Page5
  alias HologramFeatureTests.Realtime.Page6
  alias HologramFeatureTests.Realtime.Page7
  alias HologramFeatureTests.Realtime.Page8

  @channel_1 {:room, 1}
  @channel_2 {:room, 2}

  feature "broadcast from outside a Hologram handler", %{session: session} do
    session = visit(session, Page1)

    Realtime.broadcast_action(@channel_1, :show, message: "delivered")

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

  feature "subscriptions are restored after SSE reconnect with stored receipts", %{
    session: session
  } do
    session = visit(session, Page1)

    simulate_sse_disconnect(current_instance_id())

    session =
      session
      |> wait_for_no_subscription(@channel_1)
      |> wait_for_subscription(@channel_1)

    Realtime.broadcast_action(@channel_1, :show, message: "delivered after reconnect")

    assert_text(session, css("#received"), "delivered after reconnect")
  end

  feature "unsubscribe_all on an offline client takes effect on reconnect", %{
    session: session
  } do
    # Page2 subscribes to both @channel_1 and @channel_2 in init/3. We tombstone
    # only @channel_1 while the SSE is dead and assert that on reconnect the
    # @channel_1 receipt is rejected (no binding restored) while the @channel_2
    # receipt validates normally.
    session = visit(session, Page2)

    instance_id = current_instance_id()
    simulate_sse_disconnect(instance_id)

    # Wait for the registry GC so the subsequent wait_for_subscription/2 below
    # doesn't match the stale pre-kill entry (which still carries both
    # bindings) and return before the JS-driven reconnect has even started.
    # The tombstone write itself doesn't need the GC - it just needs to land
    # before the reconnect POSTs the handshake (~250ms backoff is ample).
    session = wait_for_no_subscription(session, @channel_1)
    Realtime.unsubscribe_all({:instance, instance_id}, @channel_1)

    # On reconnect only the @channel_2 binding restores in the new entry; the
    # tombstoned @channel_1 receipt is rejected at handshake verification.
    session = wait_for_subscription(session, @channel_2)

    Realtime.broadcast_action(@channel_1, :show_1, message: "blocked")
    Realtime.broadcast_action(@channel_2, :show_2, message: "delivered")

    session
    |> assert_text(css("#received-1"), "none")
    |> assert_text(css("#received-2"), "delivered")
  end

  feature "unsubscribe_all drops every cid binding on the channel", %{session: session} do
    session = visit(session, Page8)

    Realtime.unsubscribe_all({:instance, current_instance_id()}, @channel_1)

    session
    |> click(button("Broadcast"))
    |> assert_text(css("#received-page"), "delivered")
    |> assert_text(css("#received-component-1"), "none")
    |> assert_text(css("#received-component-2"), "none")
  end
end
