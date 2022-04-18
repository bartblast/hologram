defmodule HologramE2E.TemplatesTest do
  use HologramE2E.TestCase, async: false

  describe "if directive" do
    feature "element node", %{session: session} do
      session
      |> visit("/e2e/page-9")
      |> assert_has(css("#div-1", text: "Element displayed"))
      |> refute_has(css("#div-2", text: "Element not displayed"))
    end
  end
end
