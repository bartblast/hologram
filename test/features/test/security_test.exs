defmodule HologramFeatureTests.SecurityTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Security.Page1
  alias HologramFeatureTests.Security.Page2

  describe "CSRF Protection" do
    feature "initial page request is successful", %{session: session} do
      session
      |> visit(Page1)
      |> click(button("Test Action 1"))
      |> assert_text(css("#result"), "%{b: 101}")
    end

    feature "subsequent page request is successful", %{session: session} do
      session
      |> visit(Page1)
      |> click(link("Navigate to Page 2"))
      |> assert_page(Page2)
      |> click(button("Test Action 2"))
      |> assert_text(css("#result"), "%{n: 301}")
    end

    feature "command request is successful when CSRF token is present", %{session: session} do
      session
      |> visit(Page1)
      |> assert_text("CSRF Test Page 1")
      |> assert_text("CSRF Token status: Present")
      |> click(css("#test-command-btn"))
      |> assert_text(css("#command-result"), ~r/\{:success, %\{message: "Hello from Page 1!"\}\}/)
    end

    feature "command request fails when CSRF token is deleted", %{session: session} do
      session
      |> visit(Page1)
      |> assert_text("CSRF Test Page 1")
      |> assert_text("CSRF Token status: Present")
      # Delete the CSRF token from globalThis.hologram
      |> execute_script("delete globalThis.hologram.csrfToken;")
      # Update the status display to reflect the change
      |> execute_script("window.updateCsrfTokenStatus();")
      |> assert_text("CSRF Token status: Missing")

      # Attempting to execute a command should now fail
      assert_client_error(
        session,
        HologramRuntimeError,
        "command failed: 403",
        fn -> click(session, css("#test-command-btn")) end
      )

      # The command result should remain unchanged (still nil)
      session
      |> assert_text(css("#command-result"), "nil")
    end

    feature "CSRF token validation prevents cross-site request forgery", %{session: session} do
      session
      |> visit(Page1)
      |> assert_text("CSRF Test Page 1")
      |> assert_text("CSRF Token status: Present")
      # Replace the CSRF token with an invalid one
      |> execute_script("globalThis.hologram.csrfToken = 'invalid-token-12345';")
      |> execute_script("window.updateCsrfTokenStatus();")
      # Token is present but invalid
      |> assert_text("CSRF Token status: Present")

      # Attempting to execute a command should fail due to invalid token
      assert_client_error(
        session,
        HologramRuntimeError,
        "command failed: 403",
        fn -> click(session, css("#test-command-btn")) end
      )

      # The command result should remain unchanged (still nil)
      session
      |> assert_text(css("#command-result"), "nil")
    end

    feature "CSRF token works correctly after multiple page navigations", %{session: session} do
      session
      |> visit(Page1)
      |> assert_text("CSRF Test Page 1")
      |> assert_text("CSRF Token status: Present")

      # Execute command on Page 1
      |> click(css("#test-command-btn"))
      |> assert_text(css("#command-result"), ~r/\{:success, %\{message: "Hello from Page 1!"\}\}/)

      # Navigate to Page 2
      |> click(link("Navigate to Page 2"))
      |> assert_page(Page2)
      |> assert_text("CSRF Test Page 2")
      |> assert_text("CSRF Token status: Present")

      # Execute command on Page 2
      |> click(css("#test-command-btn"))
      |> assert_text(css("#command-result"), ~r/\{:success, %\{message: "Hello from Page 2!"\}\}/)

      # Navigate back to Page 1
      |> click(link("Navigate back to Page 1"))
      |> assert_page(Page1)
      |> assert_text("CSRF Test Page 1")
      |> assert_text("CSRF Token status: Present")

      # Execute command again on Page 1 to verify CSRF still works
      |> click(css("#test-command-btn"))
      |> assert_text(css("#command-result"), ~r/\{:success, %\{message: "Hello from Page 1!"\}\}/)
    end
  end
end
