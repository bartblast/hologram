# credo:disable-for-this-file Credo.Check.Refactor.VariableRebinding
defmodule HologramFeatureTests.RealtimeTest do
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.Realtime
  alias Hologram.Router
  alias HologramFeatureTests.Realtime.Page1
  alias HologramFeatureTests.Realtime.Page10
  alias HologramFeatureTests.Realtime.Page11
  alias HologramFeatureTests.Realtime.Page12
  alias HologramFeatureTests.Realtime.Page13
  alias HologramFeatureTests.Realtime.Page14
  alias HologramFeatureTests.Realtime.Page15
  alias HologramFeatureTests.Realtime.Page16
  alias HologramFeatureTests.Realtime.Page17
  alias HologramFeatureTests.Realtime.Page18
  alias HologramFeatureTests.Realtime.Page19
  alias HologramFeatureTests.Realtime.Page2
  alias HologramFeatureTests.Realtime.Page20
  alias HologramFeatureTests.Realtime.Page21
  alias HologramFeatureTests.Realtime.Page3
  alias HologramFeatureTests.Realtime.Page4
  alias HologramFeatureTests.Realtime.Page5
  alias HologramFeatureTests.Realtime.Page6
  alias HologramFeatureTests.Realtime.Page7
  alias HologramFeatureTests.Realtime.Page8
  alias HologramFeatureTests.Realtime.Page9

  @channel_1 {:room, 1}
  @channel_2 {:room, 2}
  @channel_9 {:room, 9}

  describe "broadcasting" do
    @sessions 2
    feature "from inside a handler", %{sessions: [session_1, session_2]} do
      session_1 = visit(session_1, Page7)
      session_2 = visit(session_2, Page7)

      # Both connections must be subscribed before the broadcast.
      wait_for_subscription(session_2, @channel_1, 2)

      click(session_1, button("Broadcast"))

      assert_text(session_1, css("#received"), "delivered")
      assert_text(session_2, css("#received"), "delivered")
    end

    @sessions 2
    feature "from outside a handler", %{sessions: [session_1, session_2]} do
      session_1 = visit(session_1, Page1)
      session_2 = visit(session_2, Page1)

      # Both connections must be subscribed before the broadcast.
      wait_for_subscription(session_2, @channel_1, 2)

      Realtime.broadcast_action(@channel_1, :show, message: "delivered")

      assert_text(session_1, css("#received"), "delivered")
      assert_text(session_2, css("#received"), "delivered")
    end

    @sessions 2
    feature "reaches only the page subscribed to the channel, not another page subscribed to a different channel",
            %{sessions: [session_1, session_2]} do
      # session_1 (Page1) subscribes to @channel_1 and session_2 (Page18) to
      # @channel_2. A broadcast to @channel_1 reaches session_1 and not session_2:
      # an instance receives a broadcast only when its page subscribed to that
      # channel.
      session_1 = visit(session_1, Page1)
      session_2 = visit(session_2, Page18)

      wait_for_subscription(session_1, @channel_1)
      wait_for_subscription(session_2, @channel_2)

      Realtime.broadcast_action(@channel_1, :show, message: "delivered to subscriber")

      assert_text(session_1, css("#received"), "delivered to subscriber")
      refute_text(session_2, css("#received"), "delivered to subscriber", wait_time: 1_000)
    end

    @sessions 2
    feature "reaches only the component subscribed to the channel, not a same-cid component subscribed to a different channel",
            %{sessions: [session_1, session_2]} do
      # Both sessions render Page19's "widget" component (same cid), but session_1
      # mounts it at room 1 (subscribes @channel_1) and session_2 at room 2
      # (subscribes @channel_2). A broadcast to @channel_1 reaches session_1's
      # widget and not session_2's: even with a shared cid, delivery follows the
      # channel subscription.
      session_1 = visit(session_1, Page19, room: 1)
      session_2 = visit(session_2, Page19, room: 2)

      wait_for_subscription(session_1, @channel_1)
      wait_for_subscription(session_2, @channel_2)

      Realtime.broadcast_action(@channel_1, :show, message: "delivered to widget")

      assert_text(session_1, css("#received-widget"), "delivered to widget")
      refute_text(session_2, css("#received-widget"), "delivered to widget", wait_time: 1_000)
    end
  end

  describe "broadcast exclusions" do
    @sessions 3
    feature "an instance, from inside a handler", %{
      sessions: [session_a1, session_a2, session_b]
    } do
      # A2 is a second tab of A1's session (same session, different instance); B is
      # a separate session. All three on Page7, subscribed to @channel_1.
      session_a1 = visit(session_a1, Page7)
      session_a2 = visit_as_sibling(session_a2, session_a1, Page7)
      session_b = visit(session_b, Page7)

      # All three must be subscribed first, else the refute below could pass
      # without the exclusion ever being exercised.
      wait_for_subscription(session_b, @channel_1, 3)

      # A1 excludes its own instance, so only A1's tab is skipped: its same-session
      # sibling A2 and the unrelated B both still receive (instance exclusion is
      # per-connection, not per-session).
      session_a1 = click(session_a1, button("Exclude instance"))

      assert_text(session_a2, css("#received"), "delivered to everyone else")
      assert_text(session_b, css("#received"), "delivered to everyone else")

      refute_text(session_a1, css("#received"), "delivered to everyone else", wait_time: 1_000)
    end

    @sessions 3
    feature "an instance, from outside a handler", %{
      sessions: [session_a1, session_a2, session_b]
    } do
      # Connect A1 first so its instance id can be captured while it is the only
      # registered connection. A2 is a second tab of A1's session (same session,
      # different instance); B is a separate session.
      session_a1 = visit(session_a1, Page1)
      instance_a1 = current_instance_id()

      session_a2 = visit_as_sibling(session_a2, session_a1, Page1)
      session_b = visit(session_b, Page1)

      # All three must be subscribed first, else the refute below could pass
      # without the exclusion ever being exercised.
      wait_for_subscription(session_b, @channel_1, 3)

      # Excluding A1's instance skips only that one connection: its same-session
      # sibling A2 and the unrelated B both still receive (instance exclusion is
      # per-connection, not per-session).
      Realtime.broadcast_action_except(
        {:instance, instance_a1},
        @channel_1,
        :show,
        message: "delivered to the rest"
      )

      assert_text(session_a2, css("#received"), "delivered to the rest")
      assert_text(session_b, css("#received"), "delivered to the rest")

      refute_text(session_a1, css("#received"), "delivered to the rest", wait_time: 1_000)
    end

    @sessions 3
    feature "a session, from inside a handler", %{
      sessions: [session_a1, session_a2, session_b]
    } do
      # A2 is a second tab of A1's session (same session, different instance); B is
      # a separate session. All three on Page7, subscribed to @channel_1.
      session_a1 = visit(session_a1, Page7)
      session_a2 = visit_as_sibling(session_a2, session_a1, Page7)
      session_b = visit(session_b, Page7)

      # All three must be subscribed first, else the refute below could pass
      # without the exclusion ever being exercised.
      wait_for_subscription(session_b, @channel_1, 3)

      # A1 excludes its own session, so every tab of that session is skipped: both
      # A1 and its same-session sibling A2 miss the broadcast, while the unrelated B
      # still receives (session exclusion reaches all connections of the session).
      session_a1 = click(session_a1, button("Exclude session"))

      assert_text(session_b, css("#received"), "delivered to all other sessions")

      refute_text(
        session_a1,
        css("#received"),
        "delivered to all other sessions",
        wait_time: 1_000
      )

      refute_text(
        session_a2,
        css("#received"),
        "delivered to all other sessions",
        wait_time: 1_000
      )
    end

    @sessions 3
    feature "a session, from outside a handler", %{
      sessions: [session_a1, session_a2, session_b]
    } do
      # Connect A1 first so its session id can be captured while it is the only
      # registered connection. A2 is a second tab of A1's session (same session
      # id, different instance); B is a separate Wallaby session (different session
      # id).
      session_a1 = visit(session_a1, Page1)
      session_a1_id = current_session_id()

      session_a2 = visit_as_sibling(session_a2, session_a1, Page1)
      session_b = visit(session_b, Page1)

      # All three must be subscribed first, else the refute below could pass
      # without the exclusion ever being exercised.
      wait_for_subscription(session_b, @channel_1, 3)

      # Excluding A1's session skips every connection of that session: both A1 and
      # its same-session sibling A2 miss the broadcast, while B (a different
      # session) receives (session exclusion reaches all connections of the
      # session).
      Realtime.broadcast_action_except(
        {:session, session_a1_id},
        @channel_1,
        :show,
        message: "delivered to other sessions"
      )

      assert_text(session_b, css("#received"), "delivered to other sessions")

      refute_text(session_a1, css("#received"), "delivered to other sessions", wait_time: 1_000)
      refute_text(session_a2, css("#received"), "delivered to other sessions", wait_time: 1_000)
    end

    @sessions 3
    feature "a user, from inside a handler (anonymous clients still receive)", %{
      sessions: [session_a1, session_a2, session_b]
    } do
      # A1 and A2 are two independent logins as the same user 1 (separate sessions,
      # not cookie-shared - a shared cookie would share the session and couldn't
      # distinguish user-scope from session-scope). B is anonymous.
      session_a1 = visit(session_a1, Page12, user_id: 1)
      session_a2 = visit(session_a2, Page12, user_id: 1)
      session_b = visit(session_b, Page1)

      # All three must be subscribed first, else the refute below could pass
      # without the exclusion ever being exercised.
      wait_for_subscription(session_b, @channel_1, 3)

      # A1 excludes its own user, so every session of that user is skipped: both A1
      # and the same-user-different-session A2 miss the broadcast, while the
      # anonymous B (no user identity to match) receives.
      session_a1 = click(session_a1, button("Exclude user"))

      assert_text(session_b, css("#received"), "delivered to all other users")

      refute_text(session_a1, css("#received"), "delivered to all other users", wait_time: 1_000)
      refute_text(session_a2, css("#received"), "delivered to all other users", wait_time: 1_000)
    end

    @sessions 3
    feature "a user, from outside a handler (anonymous clients still receive)", %{
      sessions: [session_a1, session_a2, session_b]
    } do
      # A1 and A2 are two independent logins as the same user 1 (separate sessions,
      # not cookie-shared - a shared cookie would share the session and couldn't
      # distinguish user-scope from session-scope). B is anonymous. All subscribe
      # to @channel_1.
      session_a1 = visit(session_a1, Page12, user_id: 1)
      session_a2 = visit(session_a2, Page12, user_id: 1)
      session_b = visit(session_b, Page1)

      # All three must be subscribed first, else the refute below could pass
      # without the exclusion ever being exercised.
      wait_for_subscription(session_b, @channel_1, 3)

      # Excluding user 1 skips every session of that user: both A1 and the
      # same-user-different-session A2 miss the broadcast, while the anonymous B
      # (no user identity to match) receives.
      Realtime.broadcast_action_except(
        {:user, 1},
        @channel_1,
        :show,
        message: "delivered to anonymous clients"
      )

      assert_text(session_b, css("#received"), "delivered to anonymous clients")

      refute_text(
        session_a1,
        css("#received"),
        "delivered to anonymous clients",
        wait_time: 1_000
      )

      refute_text(
        session_a2,
        css("#received"),
        "delivered to anonymous clients",
        wait_time: 1_000
      )
    end

    @sessions 3
    feature "a user, from inside a handler (other users still receive)", %{
      sessions: [session_a1, session_a2, session_b]
    } do
      # A1 and A2 are two independent logins as the same user 1 (separate sessions,
      # not cookie-shared - a shared cookie would share the session and couldn't
      # distinguish user-scope from session-scope). B is logged in as user 2.
      session_a1 = visit(session_a1, Page12, user_id: 1)
      session_a2 = visit(session_a2, Page12, user_id: 1)
      session_b = visit(session_b, Page12, user_id: 2)

      # All three must be subscribed first, else the refute below could pass
      # without the exclusion ever being exercised.
      wait_for_subscription(session_b, @channel_1, 3)

      # A1 excludes its own user, so every session of that user is skipped: both A1
      # and the same-user-different-session A2 miss the broadcast, while user 2's B
      # still receives (user exclusion reaches all of a user's connections).
      session_a1 = click(session_a1, button("Exclude user"))

      assert_text(session_b, css("#received"), "delivered to all other users")

      refute_text(session_a1, css("#received"), "delivered to all other users", wait_time: 1_000)
      refute_text(session_a2, css("#received"), "delivered to all other users", wait_time: 1_000)
    end

    @sessions 3
    feature "a user, from outside a handler (other users still receive)", %{
      sessions: [session_a1, session_a2, session_b]
    } do
      # A1 and A2 are two independent logins as the same user 1 (separate sessions,
      # not cookie-shared - a shared cookie would share the session and couldn't
      # distinguish user-scope from session-scope). B is user 2. All subscribe to
      # @channel_1.
      session_a1 = visit(session_a1, Page12, user_id: 1)
      session_a2 = visit(session_a2, Page12, user_id: 1)
      session_b = visit(session_b, Page12, user_id: 2)

      # All three must be subscribed first, else the refute below could pass
      # without the exclusion ever being exercised.
      wait_for_subscription(session_b, @channel_1, 3)

      # Excluding user 1 skips every session of that user: both A1 and the
      # same-user-different-session A2 miss the broadcast, while B (a different
      # user) receives.
      Realtime.broadcast_action_except(
        {:user, 1},
        @channel_1,
        :show,
        message: "delivered to other users"
      )

      assert_text(session_b, css("#received"), "delivered to other users")

      refute_text(session_a1, css("#received"), "delivered to other users", wait_time: 1_000)
      refute_text(session_a2, css("#received"), "delivered to other users", wait_time: 1_000)
    end
  end

  describe "granting subscriptions" do
    feature "from inside a handler", %{session: session} do
      # Page11 declares no subscription in init, so the client starts unbound. A
      # command handler then subscribes the connection to @channel_1 via
      # put_subscription; gate on the registry reflecting it before broadcasting.
      session =
        session
        |> visit(Page11)
        |> click(button("Subscribe"))
        |> wait_for_subscription(@channel_1)

      Realtime.broadcast_action(@channel_1, :show, message: "delivered after subscribing")

      assert_text(session, css("#received"), "delivered after subscribing")
    end

    feature "from outside a handler", %{session: session} do
      # Page11 declares no subscription in init, so the live client starts with no
      # binding on @channel_1.
      session = visit(session, Page11)

      # The server grants a {@channel_1, "page"} binding to the live connection;
      # gate on the registry reflecting it before broadcasting.
      Realtime.subscribe({:instance, current_instance_id()}, @channel_1, "page")
      session = wait_for_subscription(session, @channel_1)

      Realtime.broadcast_action(@channel_1, :show, message: "delivered on granted subscription")

      assert_text(session, css("#received"), "delivered on granted subscription")
    end
  end

  describe "dropping subscriptions" do
    feature "from inside a handler (the same cid still receives on another channel)", %{
      session: session
    } do
      # Page2's page cid subscribes to @channel_1 and @channel_2. The command
      # deletes its @channel_1 binding, then broadcasts on both: @channel_2 (the
      # same cid on another channel) still delivers while @channel_1 does not.
      session = visit(session, Page2)

      # Both bindings must exist before the drop, or "received-1 = none" is vacuous.
      wait_for_subscription(session, @channel_1)
      wait_for_subscription(session, @channel_2)

      session
      |> click(button("Unsubscribe and broadcast"))
      |> assert_text(css("#received-2"), "delivered")
      |> refute_text(css("#received-1"), "delivered", wait_time: 1_000)
    end

    feature "from outside a handler (the same cid still receives on another channel)", %{
      session: session
    } do
      # Same shape as the inside case, driven via Realtime.unsubscribe: dropping
      # the page cid's @channel_1 binding leaves its @channel_2 binding intact.
      session = visit(session, Page2)

      # Both bindings must exist before the drop, or "received-1 = none" is vacuous.
      wait_for_subscription(session, @channel_1)
      wait_for_subscription(session, @channel_2)

      # unsubscribe is async (announce-topic broadcast), so gate on the drop
      # landing before broadcasting.
      Realtime.unsubscribe({:instance, current_instance_id()}, @channel_1, "page")
      session = wait_for_no_subscription(session, @channel_1)

      Realtime.broadcast_action(@channel_1, :show_1, message: "blocked")
      Realtime.broadcast_action(@channel_2, :show_2, message: "delivered to other channel")

      session
      |> assert_text(css("#received-2"), "delivered to other channel")
      |> refute_text(css("#received-1"), "blocked", wait_time: 1_000)
    end

    feature "from inside a handler (a sibling cid on the same channel still receives)", %{
      session: session
    } do
      # Page13 hosts two components on @channel_1 (cids "component_1" and
      # "component_3"). Component 3's command deletes its own {@channel_1, cid}
      # binding, then broadcasts on @channel_1: the sibling component 1 still
      # receives while component 3 does not.
      session = visit(session, Page13)

      # Both cid bindings must exist before the drop; they share one connection, so
      # gate each cid (a connection count can't tell them apart).
      wait_for_subscription(session, @channel_1, 1, "component_1")
      wait_for_subscription(session, @channel_1, 1, "component_3")

      session
      |> click(button("Unsubscribe and broadcast"))
      |> assert_text(css("#received-component-1"), "delivered to sibling cid")
      |> refute_text(css("#received-component-3"), "delivered to sibling cid", wait_time: 1_000)
    end

    feature "from outside a handler (a sibling cid on the same channel still receives)", %{
      session: session
    } do
      # Page8 binds two components to @channel_1 (cids "component_1" and
      # "component_2"). A per-binding unsubscribe targets only "component_1", so a
      # subsequent broadcast still reaches the sibling "component_2" binding on the
      # same channel and the page's @channel_2 binding.
      session = visit(session, Page8)

      # All three bindings must exist before the drop; gate each cid since they
      # share one connection.
      wait_for_subscription(session, @channel_1, 1, "component_1")
      wait_for_subscription(session, @channel_1, 1, "component_2")
      wait_for_subscription(session, @channel_2)

      # unsubscribe is async, so gate on component_1's binding being gone before
      # broadcasting.
      Realtime.unsubscribe({:instance, current_instance_id()}, @channel_1, "component_1")
      session = wait_for_no_subscription(session, @channel_1, "component_1")

      session
      |> click(button("Broadcast"))
      |> assert_text(css("#received-page"), "delivered")
      |> refute_text(css("#received-component-1"), "delivered", wait_time: 1_000)
      |> assert_text(css("#received-component-2"), "delivered")
    end

    feature "from outside a handler (unsubscribe_all drops every cid binding)", %{
      session: session
    } do
      session = visit(session, Page8)

      # All bindings must exist before the drop; gate each cid (shared connection).
      wait_for_subscription(session, @channel_1, 1, "component_1")
      wait_for_subscription(session, @channel_1, 1, "component_2")
      wait_for_subscription(session, @channel_2)

      # unsubscribe_all is async, so gate on @channel_1 being cleared before
      # broadcasting.
      Realtime.unsubscribe_all({:instance, current_instance_id()}, @channel_1)
      session = wait_for_no_subscription(session, @channel_1)

      session
      |> click(button("Broadcast"))
      |> assert_text(css("#received-page"), "delivered")
      |> refute_text(css("#received-component-1"), "delivered", wait_time: 1_000)
      |> refute_text(css("#received-component-2"), "delivered", wait_time: 1_000)
    end
  end

  describe "subscriptions across navigation" do
    feature "dropped when navigating to a different page", %{session: session} do
      session =
        session
        |> visit(Page3)
        |> click(link("Go to Page 4"))
        |> assert_page(Page4)

      # Page 4 is subscribed to @channel_2, and Page 3's @channel_1 binding must be
      # dropped, before broadcasting - else "received-1 = none" is vacuous.
      wait_for_subscription(session, @channel_2)
      session = wait_for_no_subscription(session, @channel_1)

      session
      |> click(button("Broadcast"))
      |> assert_text(css("#received-2"), "delivered")
      |> refute_text(css("#received-1"), "delivered", wait_time: 1_000)
    end

    feature "shared layout subscription persists", %{session: session} do
      session =
        session
        |> visit(Page5)
        |> click(link("Go to Page 6"))
        |> assert_page(Page6)

      # The shared layout's @channel_9 binding must persist across the navigation
      # before broadcasting.
      wait_for_subscription(session, @channel_9)

      session
      |> click(button("Broadcast"))
      |> assert_text(css("#received-shared"), "delivered")
    end

    feature "survive history back from an external page", %{session: session} do
      session = visit(session, Page1)

      instance_id = current_instance_id()

      session =
        session
        |> visit("/external")
        |> assert_text("External Page")
        |> go_back()
        |> assert_page(Page1)
        |> wait_for_subscription(@channel_1)

      # The restored page reuses the preserved client-side instance id rather than
      # minting a fresh one, so the registry re-attaches under the same key. A
      # different value here would mean the page was reloaded from scratch instead
      # of restored (bfcache or page-snapshot path).
      assert current_instance_id() == instance_id

      Realtime.broadcast_action(@channel_1, :show, message: "delivered after back navigation")

      assert_text(session, css("#received"), "delivered after back navigation")
    end
  end

  describe "subscriptions across reconnect" do
    feature "restored after SSE reconnect with stored receipts", %{session: session} do
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
      |> refute_text(css("#received-1"), "blocked", wait_time: 1_000)
      |> assert_text(css("#received-2"), "delivered")
    end

    feature "reload fail-safe re-establishes the session when no receipt validates", %{
      session: session
    } do
      # Page1 subscribes to a single channel. Tombstoning that channel while the
      # SSE is dead leaves the client holding a receipt that no longer validates,
      # so the reconnect handshake returns no bindings at all. With receipts on
      # hand but none honored, the client gives up the in-place reconnect and does
      # a full page reload - re-mounting under a fresh instance id and
      # re-subscribing from scratch (contrast the offline unsubscribe_all case
      # above, where a surviving channel keeps the in-place reconnect alive).
      session = visit(session, Page1)

      instance_id = current_instance_id()
      simulate_sse_disconnect(instance_id)

      session = wait_for_no_subscription(session, @channel_1)
      Realtime.unsubscribe_all({:instance, instance_id}, @channel_1)

      session = wait_for_subscription(session, @channel_1)

      # The fresh instance id proves the page reloaded rather than reconnecting in
      # place, and the channel re-subscribes cleanly so broadcasts dispatch again.
      assert current_instance_id() != instance_id

      Realtime.broadcast_action(@channel_1, :show, message: "delivered after reload")

      assert_text(session, css("#received"), "delivered after reload")
    end
  end

  describe "subscriptions across identity changes" do
    feature "logout drops user-authorized subscriptions in place", %{session: session} do
      # Page9 subscribes to @channel_1 while logged in, so the binding is
      # authorized under that user. Logging out (server.user_id -> nil in the
      # command handler) makes the SSE process drop that binding in place via the
      # identity-change announce - no full page reload.
      session = visit(session, Page9)

      # Gate on the subscription before the first broadcast.
      session = wait_for_subscription(session, @channel_1)

      instance_id = current_instance_id()

      Realtime.broadcast_action(@channel_1, :show, message: "delivered while authed")
      session = assert_text(session, css("#received"), "delivered while authed")

      session =
        session
        |> click(button("Log out"))
        |> wait_for_no_subscription(@channel_1)

      # Same instance id confirms no full page reload happened.
      assert current_instance_id() == instance_id

      # The dropped binding means this broadcast must never reach the client.
      # Give it time to (not) arrive before refuting that it ever showed up.
      Realtime.broadcast_action(@channel_1, :show, message: "blocked after logout")

      refute_text(session, css("#received"), "blocked after logout", wait_time: 1_000)
    end

    @sessions 2
    feature "logout drops user-authorized subscriptions across tabs in the session", %{
      sessions: [tab_a, tab_b]
    } do
      # Tab A establishes the session (logged in as user 1, subscribed to
      # @channel_1 under that user).
      tab_a = visit(tab_a, Page9)

      # Tab B joins the SAME session by reusing tab A's signed session cookie, so
      # both SSE connections sit under one session_id and share its announce
      # topic. Wallaby sessions otherwise have isolated cookie jars; a cookie can
      # only be set once the browser is on the domain, hence the priming visit.
      %{"value" => session_cookie} =
        tab_a
        |> cookies()
        |> Enum.find(&(&1["name"] == "phoenix_session"))

      tab_b =
        tab_b
        |> visit("/external")
        |> set_cookie("phoenix_session", session_cookie)
        |> visit(Page9)

      # Both tabs must be subscribed before the first broadcast.
      wait_for_subscription(tab_b, @channel_1, 2)

      # Both tabs are subscribed, so the broadcast reaches both.
      Realtime.broadcast_action(@channel_1, :show, message: "delivered while authed")
      tab_a = assert_text(tab_a, css("#received"), "delivered while authed")
      tab_b = assert_text(tab_b, css("#received"), "delivered while authed")

      # Tab A logs out. The identity-change announce on the shared session topic
      # reaches both SSE processes, dropping the user-1 binding on each.
      tab_a = click(tab_a, button("Log out"))
      wait_for_no_subscription(tab_a, @channel_1)

      Realtime.broadcast_action(@channel_1, :show, message: "blocked after logout")

      # Both tabs converge: the post-logout broadcast dispatches on neither, and
      # neither reloaded (each still shows its pre-logout value, not "none").
      refute_text(tab_a, css("#received"), "blocked after logout", wait_time: 1_000)
      assert_text(tab_a, css("#received"), "delivered while authed")
      refute_text(tab_b, css("#received"), "blocked after logout")
      assert_text(tab_b, css("#received"), "delivered while authed")
    end

    @sessions 2
    feature "logout via terminal middleware drops user-authorized subscriptions across the session",
            %{sessions: [tab_a, tab_b]} do
      # Tab A establishes the session logged in as user 1, subscribed to
      # @channel_1 under that user. Tab B joins the SAME session, so both SSE
      # connections share the session announce topic.
      tab_a = visit(tab_a, Page9)
      tab_b = visit_as_sibling(tab_b, tab_a, Page9)

      # Both tabs must be subscribed before the logout.
      wait_for_subscription(tab_b, @channel_1, 2)

      Realtime.broadcast_action(@channel_1, :show, message: "delivered while authed")
      tab_b = assert_text(tab_b, css("#received"), "delivered while authed")

      # Tab A navigates to a page whose middleware logs out (user_id -> nil) and
      # redirects to the sign-in page. The terminal (redirect) path still
      # announces the identity change on the shared session topic, so tab B's
      # still-live connection drops its user-1 binding even though the command
      # never ran.
      tab_a
      |> visit(Router.Helpers.page_path(Page20))
      |> assert_text("Please sign in")

      wait_for_no_subscription(tab_b, @channel_1)

      # The dropped binding means the post-logout broadcast never reaches tab B,
      # and tab B did not reload (it still shows its pre-logout value, not "none").
      Realtime.broadcast_action(@channel_1, :show, message: "blocked after logout")

      refute_text(tab_b, css("#received"), "blocked after logout", wait_time: 1_000)
      assert_text(tab_b, css("#received"), "delivered while authed")
    end

    @sessions 2
    feature "re-auth via terminal middleware moves the session's connections to the new user identity",
            %{sessions: [tab_a, tab_b]} do
      # Tab A is the stationary connection under test; both tabs share a session
      # logged in as user 1, subscribed to @channel_1 under that user.
      tab_a = visit(tab_a, Page9)
      tab_b = visit_as_sibling(tab_b, tab_a, Page9)

      wait_for_subscription(tab_b, @channel_1, 2)

      # Tab B navigates to a page whose middleware re-authenticates as user 2 and
      # redirects out of the app, so its connection goes away and tab A is left as
      # the session's lone connection. The terminal (redirect) path announces the
      # identity change on the shared session topic, moving stationary tab A to
      # user 2 (and dropping its user-1 binding on the way).
      tab_b
      |> visit(Router.Helpers.page_path(Page21))
      |> assert_text("External Page")

      # Tab A drops its user-1 binding (tab B's connection is gone too), leaving it
      # the lone connection. Gate on the identity update landing before granting a
      # user-2 sub - the SSE drops the old binding before recording the new user,
      # so the drop alone does not guarantee the identity has flipped yet.
      wait_for_no_subscription(tab_a, @channel_1)
      wait_for_user_id(tab_a, 2)

      # A user-2-scoped grant on a fresh channel reaches tab A only because its
      # identity moved to user 2, and the broadcast is then delivered to it.
      Realtime.subscribe({:user, 2}, @channel_2, "page")
      tab_a = wait_for_subscription(tab_a, @channel_2)

      Realtime.broadcast_action(@channel_2, :show, message: "delivered to user 2")

      assert_text(tab_a, css("#received"), "delivered to user 2")
    end

    feature "anonymous subscription survives login and logout", %{session: session} do
      # Page10 subscribes while anonymous, so the binding is authorized under no
      # user. By the elevation rule such a binding is never dropped on an identity
      # change, so it stays live across a login and a later logout. Each broadcast
      # is gated behind wait_for_user_id so it fires only after the identity change
      # has propagated - otherwise it would race ahead and not exercise survival.
      session = visit(session, Page10)

      # Gate on the subscription before the first broadcast.
      session = wait_for_subscription(session, @channel_1)

      Realtime.broadcast_action(@channel_1, :show, message: "delivered while anonymous")
      session = assert_text(session, css("#received"), "delivered while anonymous")

      session =
        session
        |> click(button("Log in"))
        |> wait_for_user_id(1)

      Realtime.broadcast_action(@channel_1, :show, message: "delivered after login")
      session = assert_text(session, css("#received"), "delivered after login")

      session =
        session
        |> click(button("Log out"))
        |> wait_for_user_id(nil)

      Realtime.broadcast_action(@channel_1, :show, message: "delivered after logout")
      assert_text(session, css("#received"), "delivered after logout")
    end
  end

  describe "server struct fields at handler entry" do
    feature "broadcasts and subscriptions are empty at the start of a page's init/3", %{
      session: session
    } do
      session
      |> visit(Page14)
      |> assert_text(css("#broadcasts-page"), "[]")
      |> assert_text(css("#subscriptions-page"), "[]")
    end

    feature "broadcasts and subscriptions are empty at the start of a component's init/3", %{
      session: session
    } do
      session
      |> visit(Page16)
      |> assert_text(css("#broadcasts-component"), "[]")
      |> assert_text(css("#subscriptions-component"), "[]")
    end

    feature "broadcasts is empty and subscriptions holds the page's bindings at the start of a page's command/3",
            %{session: session} do
      session
      |> visit(Page15)
      # The init subscription must be registered before the command reads it.
      |> wait_for_subscription({:room, 15})
      |> click(button("Report"))
      |> assert_text(css("#broadcasts-page"), "[]")
      |> assert_text(css("#subscriptions-page"), ~s([{{:room, 15}, "page"}]))
    end

    feature "broadcasts is empty and subscriptions holds only the component's own bindings at the start of a component's command/3",
            %{session: session} do
      session
      |> visit(Page17)
      # Both the page's and the component's subscriptions must be registered before
      # the command, so a scoping regression would surface the page's binding too.
      |> wait_for_subscription({:room, 17})
      |> wait_for_subscription({:room, 18})
      |> click(button("Report"))
      |> assert_text(css("#broadcasts-component"), "[]")
      |> assert_text(css("#subscriptions-component"), ~s([{{:room, 18}, "component_5"}]))
    end
  end
end
