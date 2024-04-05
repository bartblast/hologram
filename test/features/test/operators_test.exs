defmodule HologramFeatureTests.OperatorsTest do
  use HologramFeatureTestsWeb.TestCase, async: true

  @left 123
  @right 234

  feature "*", %{session: session} do
    session
    |> visit(HologramFeatureTests.OperatorsPage)
    |> click(css("button[id='*']"))
    |> assert_text(css("#result"), inspect(@left * @right))
  end
end
