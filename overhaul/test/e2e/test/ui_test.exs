defmodule HologramE2E.UITest do
  use HologramE2E.TestCase, async: false

  alias HologramE2E.Page6
  alias HologramE2E.Page7

  describe "link" do
    feature "redirects to another page", %{session: session} do
      session
      |> visit(Page6)
      |> click(css("#test-id"))
      |> assert_has(css("h1", text: "Page 7"))
      |> assert_page(Page7)
    end

    # DEFER: test @id and @class optional props
  end
end
