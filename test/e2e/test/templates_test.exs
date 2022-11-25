defmodule HologramE2E.TemplatesTest do
  use HologramE2E.TestCase, async: false
  alias HologramE2E.Page9

  describe "if directive" do
    feature "element node", %{session: session} do
      session
      |> visit(Page9)
      |> assert_has(css("#div-1", text: "Element displayed"))
      |> refute_has(css("#div-2", text: "Element not displayed"))
    end
  end
end
