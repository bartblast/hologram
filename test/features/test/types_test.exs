defmodule HologramFeatureTests.TypesTest do
  use HologramFeatureTests.TestCase, async: true
  alias HologramFeatureTests.TypesPage

  feature "atom", %{session: session} do
    session
    |> visit(TypesPage)
    |> click(css("button[id='atom']"))
    |> assert_text(css("#result"), inspect(:abc))
  end
end
