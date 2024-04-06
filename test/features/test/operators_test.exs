defmodule HologramFeatureTests.OperatorsTest do
  use HologramFeatureTests.TestCase, async: true
  alias HologramFeatureTests.OperatorsPage

  @integer_a 123
  @integer_b 234

  feature "+", %{session: session} do
    session
    |> visit(OperatorsPage)
    |> click(css("button[id='+']"))
    |> assert_text(css("#result"), inspect(@integer_a + @integer_b))
  end

  feature "*", %{session: session} do
    session
    |> visit(OperatorsPage)
    |> click(css("button[id='*']"))
    |> assert_text(css("#result"), inspect(@integer_a * @integer_b))
  end
end
