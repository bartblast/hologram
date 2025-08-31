defmodule HologramFeatureTests.SecurityTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Security.Page1
  alias HologramFeatureTests.Security.Page2

  describe "CSRF Protection" do
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
end
