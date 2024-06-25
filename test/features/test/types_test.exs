defmodule HologramFeatureTests.TypesTest do
  use HologramFeatureTests.TestCase, async: true
  alias HologramFeatureTests.TypesPage

  feature "atom", %{session: session} do
    session
    |> visit(TypesPage)
    |> click(css("button[id='atom']"))
    |> assert_text(css("#result"), inspect(:abc))
  end

  feature "float", %{session: session} do
    session
    |> visit(TypesPage)
    |> click(css("button[id='float']"))
    |> assert_text(css("#result"), inspect(1.23))
  end

  feature "integer", %{session: session} do
    session
    |> visit(TypesPage)
    |> click(css("button[id='integer']"))
    |> assert_text(css("#result"), inspect(123))
  end
end
