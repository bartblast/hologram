defmodule HologramFeatureTests.ServerCreatedStructsTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.CallGraph.ServerCreatedStructsPage

  feature "struct created in server init renders after client re-render", %{session: session} do
    session
    |> visit(ServerCreatedStructsPage)
    |> assert_text(css("#result"), "struct(created in init)")
    |> click(button("Relabel"))
    |> assert_text(css("#label"), "relabeled")
    |> assert_text(css("#result"), "struct(created in init)")
  end
end
