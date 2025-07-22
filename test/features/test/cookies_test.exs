defmodule HologramFeatureTests.CookiesTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Cookies.PageInitPage
  alias HologramFeatureTests.EmptyPage
  alias Wallaby.Browser

  describe "page init cookies handling" do
    feature "reads existing string-encoded cookie during page init", %{session: session} do
      assert Browser.cookies(session) == []

      session
      |> visit(EmptyPage)
      |> Browser.set_cookie("cookie_key", "cookie_value")
      |> visit(PageInitPage)
      |> assert_text("cookie_value")
    end
  end
end
