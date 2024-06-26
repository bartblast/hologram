defmodule HologramFeatureTests.TypesTest do
  use HologramFeatureTests.TestCase, async: true
  alias HologramFeatureTests.TypesPage

  feature "anonymous_function_client", %{session: session} do
    session
    |> visit(TypesPage)
    |> click(css("button[id='anonymous_function_client']"))
    |> assert_text(css("#result"), inspect(4))
  end

  feature "anonymous_function_transport", %{session: session} do
    assert_raise Wallaby.JSError, ~r/can't JSON encode boxed anonymous functions/, fn ->
      session
      |> visit(TypesPage)
      |> click(css("button[id='anonymous_function_transport']"))
    end
  end

  feature "atom", %{session: session} do
    session
    |> visit(TypesPage)
    |> click(css("button[id='atom']"))
    |> assert_text(css("#result"), inspect(:abc))
  end

  feature "binary", %{session: session} do
    session
    |> visit(TypesPage)
    |> click(css("button[id='binary']"))
    |> assert_text(css("#result"), inspect("abc"))
  end

  feature "bitstring (non-binary)", %{session: session} do
    session
    |> visit(TypesPage)
    |> click(css("button[id='bitstring (non-binary)']"))
    |> assert_text(css("#result"), inspect(<<1::1, 0::1, 1::1, 0::1>>))
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
