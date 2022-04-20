defmodule HologramE2E.TypesTest do
  use HologramE2E.TestCase, async: false

  describe "anonymous function" do
    feature "regular syntax", %{session: session} do
      session
      |> visit("/e2e/types/anonymous-function")
      |> click(css("#button_regular_syntax"))
      |> assert_has(css("#text", text: "Result = true"))
    end

    # TODO: implement
    # feature "shorthand syntax"
  end
end
