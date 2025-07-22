defmodule HologramFeatureTests.CookiesTest do
  use HologramFeatureTests.TestCase, async: true

  alias Hologram.Runtime.Cookie
  alias HologramFeatureTests.Cookies.Page1
  alias HologramFeatureTests.Cookies.Page2
  alias HologramFeatureTests.Cookies.Page3
  alias HologramFeatureTests.Cookies.Page4
  alias HologramFeatureTests.Cookies.Page5
  alias HologramFeatureTests.EmptyPage
  alias Wallaby.Browser

  describe "page init cookies handling" do
    feature "writes cookie with default settings", %{session: session} do
      assert Browser.cookies(session) == []

      visit(session, Page3)

      assert Browser.cookies(session) == [
               %{
                 "domain" => "localhost",
                 "httpOnly" => true,
                 "name" => "cookie_key",
                 "path" => "/",
                 "sameSite" => "Lax",
                 "secure" => true,
                 "value" => Cookie.encode("cookie_value")
               }
             ]
    end

    feature "writes cookie with custom settings", %{session: session} do
      assert Browser.cookies(session) == []

      visit(session, Page4)

      assert Browser.cookies(session) == [
               %{
                 "domain" => "localhost",
                 "httpOnly" => false,
                 "name" => "cookie_key",
                 "path" => Page4.__route__(),
                 "sameSite" => "Strict",
                 "secure" => false,
                 "value" => Cookie.encode("cookie_value")
               }
             ]
    end

    feature "reads string-encoded cookie", %{session: session} do
      assert Browser.cookies(session) == []

      session
      |> visit(EmptyPage)
      |> Browser.set_cookie("cookie_key", "cookie_value")
      |> visit(Page1)
      |> assert_text("cookie_value")
    end

    feature "reads Hologram-encoded cookie", %{session: session} do
      assert Browser.cookies(session) == []

      session
      |> visit(EmptyPage)
      |> Browser.set_cookie("cookie_key", Cookie.encode(%{a: 1, b: 2}))
      |> visit(Page2)
      |> assert_text("%{a: 1, b: 2, c: 3}")
    end

    feature "deletes cookie", %{session: session} do
      assert Browser.cookies(session) == []

      session
      |> visit(EmptyPage)
      |> Browser.set_cookie("cookie_key", "cookie_value")
      |> visit(Page5)

      assert Browser.cookies(session) == []
    end
  end
end
