defmodule HologramFeatureTests.ServerCreatedStructsTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.CallGraph.ServerCreatedStructsPage
  alias HologramFeatureTests.StructBroadcaster

  @channel :server_created_structs

  feature "struct created in broadcast params renders on the client", %{session: session} do
    session = visit(session, ServerCreatedStructsPage)

    wait_for_subscription(session, @channel)

    StructBroadcaster.broadcast_struct(@channel)

    assert_text(session, css("#broadcast-result"), "broadcast struct(created in broadcast)")
  end

  feature "struct created in command renders on the client", %{session: session} do
    session
    |> visit(ServerCreatedStructsPage)
    |> click(button("Load struct"))
    |> assert_text(css("#command-result"), "command struct(created in command)")
  end

  feature "struct created in server init renders after client re-render", %{session: session} do
    session
    |> visit(ServerCreatedStructsPage)
    |> assert_text(css("#init-result"), "struct(created in init)")
    |> click(button("Relabel"))
    |> assert_text(css("#label"), "relabeled")
    |> assert_text(css("#init-result"), "struct(created in init)")
  end
end
