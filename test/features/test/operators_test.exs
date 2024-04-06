defmodule HologramFeatureTests.OperatorsTest do
  use HologramFeatureTests.TestCase, async: true
  alias HologramFeatureTests.OperatorsPage

  @integer_1 123
  @integer_2 234

  feature "+", %{session: session} do
    session
    |> visit(OperatorsPage)
    |> click(css("button[id='+']"))
    |> assert_text(css("#result"), inspect(@integer_1 + @integer_2))
  end

  feature "*", %{session: session} do
    session
    |> visit(OperatorsPage)
    |> click(css("button[id='*']"))
    |> assert_text(css("#result"), inspect(@integer_1 * @integer_2))
  end
end
