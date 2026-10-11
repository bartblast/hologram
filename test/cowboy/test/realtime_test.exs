defmodule HologramCowboyTests.RealtimeTest do
  use HologramCowboyTests.TestCase, async: false

  alias HologramCowboyTests.RealtimePage

  @channel {:room, 1}

  @sessions 2
  feature "a broadcast from a handler reaches every subscribed tab",
          %{sessions: [session_1, session_2]} do
    session_1 = visit(session_1, RealtimePage)
    session_2 = visit(session_2, RealtimePage)

    # Both connections must be subscribed before the broadcast.
    wait_for_subscription(session_2, @channel, 2)

    click(session_1, css("#broadcast"))

    assert_text(session_1, css("#received"), "delivered from a handler")
    assert_text(session_2, css("#received"), "delivered from a handler")
  end
end
