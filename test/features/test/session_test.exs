defmodule HologramFeatureTests.SessionTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Session.Page1
  alias HologramFeatureTests.Session.Page2
  alias HologramFeatureTests.Session.Page3
  alias Wallaby.Browser

  describe "page init session handling" do
    feature "write to session and read from session", %{session: session} do
      assert Browser.cookies(session) == []

      visit(session, Page1)

      assert [%{"name" => "phoenix_session"}] = Browser.cookies(session)

      session
      |> visit(Page2)
      |> assert_text("value = :abc")
    end

    feature "delete session entry", %{session: session} do
      assert Browser.cookies(session) == []

      session
      |> visit(Page1)
      |> visit(Page3)
      |> visit(Page2)
      |> assert_text("value = nil")
    end
  end
end
