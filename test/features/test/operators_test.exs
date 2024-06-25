defmodule HologramFeatureTests.OperatorsTest do
  use HologramFeatureTests.TestCase, async: true
  alias HologramFeatureTests.OperatorsPage

  @boolean_a true
  @boolean_b false

  @float_a 123.0

  @integer_a 123
  @integer_b 234
  @integer_c 345

  @list_a [1, 2, 3]
  @list_b [2, 3, 4]

  @string_a "aaa"
  @string_b "bbb"

  describe "overridable general operators" do
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
      |> assert_text(css("#result"), inspect(wrap_term(@boolean_a) and wrap_term(@boolean_b)))
    end

    feature "&&", %{session: session} do
      session
      |> visit(OperatorsPage)
      |> click(css("button[id='&&']"))
      |> assert_text(css("#result"), inspect(wrap_term(@boolean_a) && wrap_term(@boolean_b)))
    end

    feature "or", %{session: session} do
      session
      |> visit(OperatorsPage)
      |> click(css("button[id='or']"))
      |> assert_text(css("#result"), inspect(wrap_term(@boolean_a) or wrap_term(@boolean_b)))
    end

    feature "||", %{session: session} do
      session
      |> visit(OperatorsPage)
      |> click(css("button[id='||']"))
      |> assert_text(css("#result"), inspect(wrap_term(@boolean_a) || wrap_term(@boolean_b)))
    end

    feature "not", %{session: session} do
      session
      |> visit(OperatorsPage)
      |> click(css("button[id='not']"))
      |> assert_text(css("#result"), inspect(not @boolean_a))
    end

    feature "!", %{session: session} do
      session
      |> visit(OperatorsPage)
      |> click(css("button[id='!']"))
      |> assert_text(css("#result"), inspect(!wrap_term(@boolean_a)))
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

    feature "@", %{session: session} do
      session
      |> visit(OperatorsPage)
      |> click(css("button[id='@']"))
      |> assert_text(css("#result"), inspect(@integer_c))
    end

    feature "..", %{session: session} do
      session
      |> visit(OperatorsPage)
      |> click(css("button[id='..']"))
      |> assert_text(css("#result"), inspect(@integer_a..@integer_b))
    end

    feature "..//", %{session: session} do
      session
      |> visit(OperatorsPage)
      |> click(css("button[id='..//']"))
      |> assert_text(css("#result"), inspect(@integer_a..@integer_b//@integer_c))
    end

    feature "<>", %{session: session} do
      session
      |> visit(OperatorsPage)
      |> click(css("button[id='<>']"))
      |> assert_text(css("#result"), inspect(@string_a <> @string_b))
    end

    feature "|>", %{session: session} do
      expected =
        @integer_a
        |> OperatorsPage.fun_1()
        |> OperatorsPage.fun_2()

      session
      |> visit(OperatorsPage)
      |> click(css("button[id='|>']"))
      |> assert_text(css("#result"), inspect(expected))
    end
  end

  describe "special form operators" do
    feature "^", %{session: session} do
      session
      |> visit(OperatorsPage)
      |> click(css("button[id='^']"))
      |> assert_text(css("#result"), inspect(@integer_b))
    end

    feature ". (remote call)", %{session: session} do
      session
      |> visit(OperatorsPage)
      |> click(css("button[id='. (remote call)']"))
      |> assert_text(css("#result"), inspect([@integer_a, @integer_b, @integer_c]))
    end

    feature ". (anonymous function call)", %{session: session} do
      session
      |> visit(OperatorsPage)
      |> click(css("button[id='. (anonymous function call)']"))
      |> assert_text(css("#result"), inspect(@integer_c * @integer_c))
    end

    feature ". (map access)", %{session: session} do
      session
      |> visit(OperatorsPage)
      |> click(css("button[id='. (map access)']"))
      |> assert_text(css("#result"), inspect(@integer_b))
    end

    feature "=", %{session: session} do
      session
      |> visit(OperatorsPage)
      |> click(css("button[id='=']"))
      |> assert_text(css("#result"), inspect(@integer_a))
    end

    feature "& (remote function)", %{session: session} do
      session
      |> visit(OperatorsPage)
      |> click(css("button[id='& (remote function)']"))
      |> assert_text(css("#result"), inspect([@integer_a, @integer_b, @integer_c]))
    end

    feature "& (local function)", %{session: session} do
      session
      |> visit(OperatorsPage)
      |> click(css("button[id='& (local function)']"))
      |> assert_text(css("#result"), inspect(@integer_a * 4))
    end

    feature "& (anonymous function)", %{session: session} do
      session
      |> visit(OperatorsPage)
      |> click(css("button[id='& (anonymous function)']"))
      |> assert_text(css("#result"), inspect(@integer_a * 5))
    end

    feature "::", %{session: session} do
      session
      |> visit(OperatorsPage)
      |> click(css("button[id='::']"))
      |> assert_text(css("#result"), inspect(<<@float_a::float>>))
    end

    feature "==", %{session: session} do
      session
      |> visit(OperatorsPage)
      |> click(css("button[id='==']"))
      |> assert_text(css("#result"), inspect(@integer_a == @integer_a))
    end

    feature "===", %{session: session} do
      session
      |> visit(OperatorsPage)
      |> click(css("button[id='===']"))
      |> assert_text(css("#result"), inspect(@integer_a === @float_a))
    end
  end
end
