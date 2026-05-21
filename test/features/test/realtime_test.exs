defmodule HologramFeatureTests.RealtimeTest do
  use HologramFeatureTests.TestCase, async: false

  alias Hologram.Realtime
  alias HologramFeatureTests.Realtime.Page1

  feature "broadcast from outside a Hologram handler", %{session: session} do
    session = visit(session, Page1)

    Realtime.broadcast_action({:room, 42}, "page", :show, message: "hello from server")

    assert_text(session, css("#received"), "hello from server")
  end
end
