defmodule HologramFeatureTests.OperatorsTest do
  use HologramFeatureTests.TestCase, async: true
  alias HologramFeatureTests.OperatorsPage

  @boolean_a true
  @boolean_b false

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

  feature "and", %{session: session} do
    session
    |> visit(OperatorsPage)
    |> click(css("button[id='and']"))
    |> assert_text(css("#result"), inspect(@boolean_a and @boolean_b))
  end

  feature "&&", %{session: session} do
    session
    |> visit(OperatorsPage)
    |> click(css("button[id='&&']"))
    |> assert_text(css("#result"), inspect(build_value(@boolean_a) && build_value(@boolean_b)))
  end

  feature "or", %{session: session} do
    session
    |> visit(OperatorsPage)
    |> click(css("button[id='or']"))
    |> assert_text(css("#result"), inspect(@boolean_a or @boolean_b))
  end

  feature "||", %{session: session} do
    session
    |> visit(OperatorsPage)
    |> click(css("button[id='||']"))
    |> assert_text(css("#result"), inspect(build_value(@boolean_a) || build_value(@boolean_b)))
  end

  feature "not", %{session: session} do
    session
    |> visit(OperatorsPage)
    |> click(css("button[id='not']"))
    |> assert_text(css("#result"), inspect(not @boolean_b))
  end

  feature "!", %{session: session} do
    session
    |> visit(OperatorsPage)
    |> click(css("button[id='!']"))
    |> assert_text(css("#result"), inspect(!@boolean_a))
  end

  feature "in", %{session: session} do
    session
    |> visit(OperatorsPage)
    |> click(css("button[id='in']"))
    |> assert_text(css("#result"), inspect(@integer_a in @list_a))
  end

  feature "not in", %{session: session} do
    session
    |> visit(OperatorsPage)
    |> click(css("button[id='not in']"))
    |> assert_text(css("#result"), inspect(@integer_a not in @list_a))
  end
end
