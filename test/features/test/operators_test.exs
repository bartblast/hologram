defmodule HologramFeatureTests.OperatorsTest do
  use HologramFeatureTests.TestCase, async: true
  alias HologramFeatureTests.OperatorsPage

  @integer_a 123
  @integer_b 234
  @list_a [1, 2, 3]
  @list_b [2, 3, 4]

  feature "unary +", %{session: session} do
    session
    |> visit(OperatorsPage)
    |> click(css("button[id='unary+']"))
    |> assert_text(css("#result"), inspect(+@integer_a))
  end

  feature "unary -", %{session: session} do
    session
    |> visit(OperatorsPage)
    |> click(css("button[id='unary-']"))
    |> assert_text(css("#result"), inspect(-@integer_a))
  end

  feature "+", %{session: session} do
    session
    |> visit(OperatorsPage)
    |> click(css("button[id='+']"))
    |> assert_text(css("#result"), inspect(@integer_a + @integer_b))
  end

  feature "-", %{session: session} do
    session
    |> visit(OperatorsPage)
    |> click(css("button[id='-']"))
    |> assert_text(css("#result"), inspect(@integer_a - @integer_b))
  end

  feature "*", %{session: session} do
    session
    |> visit(OperatorsPage)
    |> click(css("button[id='*']"))
    |> assert_text(css("#result"), inspect(@integer_a * @integer_b))
  end

  feature "/", %{session: session} do
    session
    |> visit(OperatorsPage)
    |> click(css("button[id='/']"))
    |> assert_text(css("#result"), inspect(@integer_a / @integer_b))
  end

  feature "++", %{session: session} do
    session
    |> visit(OperatorsPage)
    |> click(css("button[id='++']"))
    |> assert_text(css("#result"), inspect(@list_a ++ @list_b))
  end

  feature "--", %{session: session} do
    session
    |> visit(OperatorsPage)
    |> click(css("button[id='--']"))
    |> assert_text(css("#result"), inspect(@list_a -- @list_b))
  end
end
