defmodule HologramE2E.UITest do
  use HologramE2E.TestCase, async: false

  describe "link" do
    feature "redirects to another page", %{session: session} do
      session
      |> visit("/e2e/page-6")
      |> click(css("#test-id"))
      |> assert_has(css("h1", text: "Page 7"))

      assert current_path(session) == "/e2e/page-7"
    end

    # DEFER: test @id and @class optional props
  end
end
