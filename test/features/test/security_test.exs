defmodule HologramFeatureTests.SecurityTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Security.Page1
  alias HologramFeatureTests.Security.Page2
  alias HologramFeatureTests.Security.Page3
  alias HologramFeatureTests.Security.Page4
  alias HologramFeatureTests.Security.Page5

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
    feature "text nodes escaping", %{session: session} do
      session
      |> visit(Page3)
      # no escaping
      |> assert_script_result("return window.xss1", true)
      # HTML entities
      |> assert_script_result("return window.xss2", nil)
      # server-side escaping
      |> assert_script_result("return window.xss3", nil)
      |> click(button("Show script #4"))
      # client-side escaping
      |> assert_script_result("return window.xss4", nil)
    end

    feature "attributes escaping", %{session: session} do
      session
      |> visit(Page4)
      # server-side escaping
      |> assert_script_result("return window.xss1", nil)
      |> click(button("Show div #2"))
      # client-side escaping
      |> assert_script_result("return window.xss2", nil)
    end

    feature "form inputs controlled attributes are not escaped", %{session: session} do
      session
      |> visit(Page5)
      |> click(button("Set values"))
      |> assert_input_value("#text_input", "a < b")
      |> assert_input_value("#email_input", "c < d")
      |> assert_input_value("#textarea_input", "d < e")
      |> assert_input_value("#select_input", "b < c")
    end
  end
end
