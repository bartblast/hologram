defmodule HologramFeatureTests.TypesTest do
  use HologramFeatureTests.TestCase, async: true
  alias HologramFeatureTests.TypesPage

  describe "anonymous function" do
    feature "(client origin, non-capture)", %{session: session} do
      assert_raise Wallaby.JSError,
                   ~r/can't encode client terms that are anonymous functions that are not named function captures/,
                   fn ->
                     session
                     |> visit(TypesPage)
                     |> click(css("button[id='anonymous function (client origin, non-capture)']"))
                   end

      assert_text(session, css("#result"), inspect(6))
    end

    feature "(client origin, capture)", %{session: session} do
      session
      |> visit(TypesPage)
      |> click(css("button[id='anonymous function (client origin, capture)']"))
      |> assert_text(css("#result"), inspect(6))
    end

    feature "(server origin, non-capture)", %{session: session} do
      assert_raise Wallaby.JSError, ~r/command failed/, fn ->
        session
        |> visit(TypesPage)
        |> click(css("button[id='anonymous function (server origin, non-capture)']"))
      end
    end
  end

  feature "atom", %{session: session} do
    session
    |> visit(TypesPage)
    |> click(css("button[id='atom']"))
    |> assert_text(css("#result"), inspect(:abc))
  end

  describe "bitstring" do
    feature "binary", %{session: session} do
      session
      |> visit(TypesPage)
      |> click(css("button[id='bitstring (binary)']"))
      |> assert_text(css("#result"), inspect("abc"))
    end

    feature "non-binary", %{session: session} do
      session
      |> visit(TypesPage)
      |> click(css("button[id='bitstring (non-binary)']"))
      |> assert_text(css("#result"), inspect(<<1::1, 0::1, 1::1, 0::1>>))
    end
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

  describe "PID" do
    feature "client origin", %{session: session} do
      assert_raise Wallaby.JSError,
                   ~r/can't encode client terms that are PIDs originating in client/,
                   fn ->
                     session
                     |> visit(TypesPage)
                     |> click(css("button[id='pid (client origin)']"))
                   end
    end

    feature "server origin", %{session: session} do
      session
      |> visit(TypesPage)
      |> click(css("button[id='pid (server origin)']"))
      |> assert_text(css("#result"), inspect(pid("0.11.222")))
    end
  end

  feature "tuple", %{session: session} do
    session
    |> visit(TypesPage)
    |> click(css("button[id='tuple']"))
    |> assert_text(css("#result"), inspect({123, :abc}))
  end
end
