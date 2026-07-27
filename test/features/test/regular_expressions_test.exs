defmodule HologramFeatureTests.RegularExpressionsTest do
  use HologramFeatureTests.TestCase, async: true
  alias HologramFeatureTests.RegularExpressionsPage

  feature "client-sent regex", %{session: session} do
    session
    |> visit(RegularExpressionsPage)
    |> click(css("button[id='client-sent regex']"))
    |> assert_text(css("#result"), inspect(["gggh"]))
  end

  feature "dynamic compilation", %{session: session} do
    session
    |> visit(RegularExpressionsPage)
    |> click(css("button[id='dynamic compilation']"))
    |> assert_text(css("#result"), inspect(["bb"]))
  end

  feature "match operator", %{session: session} do
    session
    |> visit(RegularExpressionsPage)
    |> click(css("button[id='match operator']"))
    |> assert_text(css("#result"), inspect(true))
  end

  feature "named captures", %{session: session} do
    session
    |> visit(RegularExpressionsPage)
    |> click(css("button[id='named captures']"))
    |> assert_text(css("#result"), inspect(%{"number" => "42"}))
  end

  feature "regex match?", %{session: session} do
    session
    |> visit(RegularExpressionsPage)
    |> click(css("button[id='regex match?']"))
    |> assert_text(css("#result"), inspect(false))
  end

  feature "regex replace", %{session: session} do
    session
    |> visit(RegularExpressionsPage)
    |> click(css("button[id='regex replace']"))
    |> assert_text(css("#result"), inspect("aXc"))
  end

  feature "regex run", %{session: session} do
    session
    |> visit(RegularExpressionsPage)
    |> click(css("button[id='regex run']"))
    |> assert_text(css("#result"), inspect(["abb", "bb"]))
  end

  feature "regex scan", %{session: session} do
    session
    |> visit(RegularExpressionsPage)
    |> click(css("button[id='regex scan']"))
    |> assert_text(css("#result"), inspect([["1"], ["3"]]))
  end

  feature "regex split", %{session: session} do
    session
    |> visit(RegularExpressionsPage)
    |> click(css("button[id='regex split']"))
    |> assert_text(css("#result"), inspect(["1", "2", "3"]))
  end

  feature "server-sent regex", %{session: session} do
    session
    |> visit(RegularExpressionsPage)
    |> click(css("button[id='server-sent regex']"))
    |> assert_text(css("#result"), inspect(["eef"]))
  end
end
