defmodule HologramFeatureTests.TypesTest do
  use HologramFeatureTests.TestCase, async: true
  alias HologramFeatureTests.TypesPage

  feature "anonymous function (client origin, non-capture)", %{session: session} do
    assert_raise Wallaby.JSError, ~r/can't JSON encode anonymous functions originating/, fn ->
      session
      |> visit(TypesPage)
      |> click(css("button[id='anonymous function (client origin, non-capture)']"))
    end

    session
    |> assert_text(css("#result"), inspect(4))
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

  feature "list", %{session: session} do
    session
    |> visit(TypesPage)
    |> click(css("button[id='list']"))
    |> assert_text(css("#result"), inspect([123, :abc]))
  end

  feature "map", %{session: session} do
    session
    |> visit(TypesPage)
    |> click(css("button[id='map']"))
    |> assert_text(css("#result"), inspect(%{a: 123, b: "abc"}))
  end

  feature "PID client origin", %{session: session} do
    assert_raise Wallaby.JSError, ~r/can't JSON encode PIDs originating in client/, fn ->
      session
      |> visit(TypesPage)
      |> click(css("button[id='pid_client_origin']"))
    end
  end

  feature "PID server origin", %{session: session} do
    session
    |> visit(TypesPage)
    |> click(css("button[id='pid_server_origin']"))
    |> assert_text(css("#result"), inspect(pid("0.11.222")))
  end

  feature "tuple", %{session: session} do
    session
    |> visit(TypesPage)
    |> click(css("button[id='tuple']"))
    |> assert_text(css("#result"), inspect({123, :abc}))
  end
end
