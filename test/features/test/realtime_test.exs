# credo:disable-for-this-file Credo.Check.Refactor.VariableRebinding
defmodule HologramFeatureTests.RealtimeTest do
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.Realtime
  alias HologramFeatureTests.Realtime.Page1
  alias HologramFeatureTests.Realtime.Page10
  alias HologramFeatureTests.Realtime.Page12
  alias HologramFeatureTests.Realtime.Page2
  alias HologramFeatureTests.Realtime.Page3
  alias HologramFeatureTests.Realtime.Page4
  alias HologramFeatureTests.Realtime.Page5
  alias HologramFeatureTests.Realtime.Page6
  alias HologramFeatureTests.Realtime.Page7
  alias HologramFeatureTests.Realtime.Page8
  alias HologramFeatureTests.Realtime.Page9

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

  feature "subscriptions survive history navigation back from an external page", %{
    session: session
  } do
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

  feature "unsubscribe_all drops every cid binding on the channel", %{session: session} do
    session = visit(session, Page8)

    Realtime.unsubscribe_all({:instance, current_instance_id()}, @channel_1)

    session
    |> click(button("Broadcast"))
    |> assert_text(css("#received-page"), "delivered")
    |> assert_text(css("#received-component-1"), "none")
    |> assert_text(css("#received-component-2"), "none")
  end

  feature "unsubscribe drops a single cid binding on the channel", %{session: session} do
    # Page8 binds two components to @channel_1 (cids "component_1" and
    # "component_2"). A per-binding unsubscribe targets only "component_1", so a
    # subsequent broadcast still reaches the sibling "component_2" binding on the
    # same channel and the page's @channel_2 binding.
    session = visit(session, Page8)

    Realtime.unsubscribe({:instance, current_instance_id()}, @channel_1, "component_1")

    session
    |> click(button("Broadcast"))
    |> assert_text(css("#received-page"), "delivered")
    |> assert_text(css("#received-component-1"), "none")
    |> assert_text(css("#received-component-2"), "delivered")
  end

  feature "logout drops user-authorized subscriptions in place", %{session: session} do
    # Page9 subscribes to @channel_1 while logged in, so the binding is
    # authorized under that user. Logging out (server.user_id -> nil in the
    # command handler) makes the SSE process drop that binding in place via the
    # identity-change announce - no full page reload.
    session = visit(session, Page9)

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

  feature "anonymous subscription survives login and logout", %{session: session} do
    # Page10 subscribes while anonymous, so the binding is authorized under no
    # user. By the elevation rule such a binding is never dropped on an identity
    # change, so it stays live across a login and a later logout. Each broadcast
    # is gated behind wait_for_user_id so it fires only after the identity change
    # has propagated - otherwise it would race ahead and not exercise survival.
    session = visit(session, Page10)

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

  @sessions 2
  feature "broadcast from outside a handler can exclude an instance", %{
    sessions: [session_a, session_b]
  } do
    # Connect A first so its instance id can be captured while it is the only
    # registered connection, then connect B.
    session_a = visit(session_a, Page1)
    instance_a = current_instance_id()
    session_b = visit(session_b, Page1)

    # Broadcasting with A's instance excluded reaches B but not A.
    Realtime.broadcast_action_except(
      {:instance, instance_a},
      @channel_1,
      :show,
      message: "delivered to the rest"
    )

    assert_text(session_b, css("#received"), "delivered to the rest")
    refute_text(session_a, css("#received"), "delivered to the rest", wait_time: 1_000)
  end

  @sessions 2
  feature "broadcast from outside a handler can exclude a session", %{
    sessions: [session_a, session_b]
  } do
    # Connect A first so its session id can be captured while it is the only
    # registered connection, then connect B (a separate Wallaby session, so a
    # different session id).
    session_a = visit(session_a, Page1)
    session_a_id = current_session_id()
    session_b = visit(session_b, Page1)

    # Broadcasting with A's session excluded reaches B (a different session) but
    # not A.
    Realtime.broadcast_action_except(
      {:session, session_a_id},
      @channel_1,
      :show,
      message: "delivered to other sessions"
    )

    assert_text(session_b, css("#received"), "delivered to other sessions")
    refute_text(session_a, css("#received"), "delivered to other sessions", wait_time: 1_000)
  end

  @sessions 2
  feature "broadcast from outside a handler can exclude a user (anonymous clients still receive)",
          %{sessions: [session_a, session_b]} do
    # A is logged in as user 1; B is anonymous. Both subscribe to @channel_1.
    session_a = visit(session_a, Page12, user_id: 1)
    session_b = visit(session_b, Page1)

    # Excluding user 1 reaches the anonymous B (no user identity to match) but
    # not A.
    Realtime.broadcast_action_except(
      {:user, 1},
      @channel_1,
      :show,
      message: "delivered to anonymous clients"
    )

    assert_text(session_b, css("#received"), "delivered to anonymous clients")
    refute_text(session_a, css("#received"), "delivered to anonymous clients", wait_time: 1_000)
  end

  @sessions 2
  feature "broadcast from outside a handler can exclude a user (other users still receive)",
          %{sessions: [session_a, session_b]} do
    # A is user 1, B is user 2. Both subscribe to @channel_1.
    session_a = visit(session_a, Page12, user_id: 1)
    session_b = visit(session_b, Page12, user_id: 2)

    # Excluding user 1 reaches B (a different user) but not A.
    Realtime.broadcast_action_except(
      {:user, 1},
      @channel_1,
      :show,
      message: "delivered to other users"
    )

    assert_text(session_b, css("#received"), "delivered to other users")
    refute_text(session_a, css("#received"), "delivered to other users", wait_time: 1_000)
  end

  @sessions 3
  feature "broadcast from inside a handler can exclude an instance", %{
    sessions: [session_a1, session_a2, session_b]
  } do
    # A2 is a second tab of A1's session (same session, different instance); B is
    # a separate session. All three on Page7, subscribed to @channel_1.
    session_a1 = visit(session_a1, Page7)
    session_a2 = visit_as_sibling(session_a2, session_a1, Page7)
    session_b = visit(session_b, Page7)

    # A1 excludes its own instance, so only A1's tab is skipped: its same-session
    # sibling A2 and the unrelated B both still receive (instance exclusion is
    # per-connection, not per-session).
    session_a1 = click(session_a1, button("Exclude instance"))

    assert_text(session_a2, css("#received"), "delivered to everyone else")
    assert_text(session_b, css("#received"), "delivered to everyone else")

    refute_text(session_a1, css("#received"), "delivered to everyone else", wait_time: 1_000)
  end

  @sessions 3
  feature "broadcast from inside a handler can exclude a session", %{
    sessions: [session_a1, session_a2, session_b]
  } do
    # A2 is a second tab of A1's session (same session, different instance); B is
    # a separate session. All three on Page7, subscribed to @channel_1.
    session_a1 = visit(session_a1, Page7)
    session_a2 = visit_as_sibling(session_a2, session_a1, Page7)
    session_b = visit(session_b, Page7)

    # A1 excludes its own session, so every tab of that session is skipped: both
    # A1 and its same-session sibling A2 miss the broadcast, while the unrelated B
    # still receives (session exclusion reaches all connections of the session).
    session_a1 = click(session_a1, button("Exclude session"))

    assert_text(session_b, css("#received"), "delivered to all other sessions")

    refute_text(session_a1, css("#received"), "delivered to all other sessions", wait_time: 1_000)
    refute_text(session_a2, css("#received"), "delivered to all other sessions", wait_time: 1_000)
  end

  @sessions 3
  feature "broadcast from inside a handler can exclude a user", %{
    sessions: [session_a1, session_a2, session_b]
  } do
    # A1 and A2 are two independent logins as the same user 1 (separate sessions,
    # not cookie-shared - a shared cookie would share the session and couldn't
    # distinguish user-scope from session-scope). B is logged in as user 2.
    session_a1 = visit(session_a1, Page12, user_id: 1)
    session_a2 = visit(session_a2, Page12, user_id: 1)
    session_b = visit(session_b, Page12, user_id: 2)

    # A1 excludes its own user, so every session of that user is skipped: both A1
    # and the same-user-different-session A2 miss the broadcast, while user 2's B
    # still receives (user exclusion reaches all of a user's connections).
    session_a1 = click(session_a1, button("Exclude user"))

    assert_text(session_b, css("#received"), "delivered to all other users")

    refute_text(session_a1, css("#received"), "delivered to all other users", wait_time: 1_000)
    refute_text(session_a2, css("#received"), "delivered to all other users", wait_time: 1_000)
  end
end
