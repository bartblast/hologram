defmodule HologramFeatureTests.SecurityTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Security.Page1
  alias HologramFeatureTests.Security.Page2
  alias HologramFeatureTests.Security.Page3
  alias HologramFeatureTests.Security.Page4

  describe "CSRF protection" do
    feature "initial page request is successful", %{session: session} do
      session
      |> visit(Page1)
      |> click(button("Test Action 1"))
      |> assert_text(css("#result"), "101")
    end

    feature "subsequent page request is successful", %{session: session} do
      session
      |> visit(Page1)
      |> click(link("Navigate to Page 2"))
      |> assert_page(Page2)
      |> click(button("Test Action 2"))
      |> assert_text(css("#result"), "301")
    end

    feature "command request is successful when CSRF token is valid", %{session: session} do
      session
      |> visit(Page1)
      |> click(button("Test Command"))
      |> assert_text(css("#result"), "201")
    end

    feature "command request fails when CSRF token is invalid", %{session: session} do
      assert_js_error session,
                      "command failed: 403",
                      fn ->
                        session
                        |> visit(Page1)
                        |> execute_script(
                          "globalThis.hologram.csrfToken = 'invalid-token-12345';"
                        )
                        |> click(button("Test Command"))
                      end
    end

    feature "command request fails when CSRF token is not present", %{session: session} do
      assert_js_error session,
                      "command failed: 403",
                      fn ->
                        session
                        |> visit(Page1)
                        |> execute_script("delete globalThis.hologram.csrfToken;")
                        |> click(button("Test Command"))
                      end
    end
  end

  describe "XSS protection" do
    feature "static content is not escaped", %{session: session} do
      session
      |> visit(Page3)
      |> assert_text(css("#my_div"), "a & b")
      |> assert_has(css("#my_div[class='c < d']"))
      |> assert_inline_script("#my_script", "window.myVar = 1 < 2;")
    end

    feature "dynamic content is escaped", %{session: session} do
      session
      |> visit(Page4)
      |> assert_text(css("#my_div"), "a &amp; b")
      |> assert_has(css("#my_div[class='c &lt; d']"))
      |> assert_inline_script("#my_script", "window.myVar = `1 &lt; 2`;")
    end
  end
end
