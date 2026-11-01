defmodule HologramFeatureTests.SessionRestoreTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.SessionRestore.AccountPage
  alias HologramFeatureTests.SessionRestore.LoginPage
  alias HologramFeatureTests.SessionRestore.ProtectedPage

  # The marker is state only the account page holds, so Back shows it only by restoring the page
  # as it was left. Each command's result is waited for before the next step, so that the identity
  # it leaves is the one the browser holds.

  # A page that is rebuilt or reloaded after a #fragment click is, a moment after the click, once
  # the handler's storage writes are done. So the page is given that moment before the marker is
  # checked.
  defp keep_marker(session) do
    refute_text(session, css("#marker"), "none", wait_time: 1_000)
  end

  # Logs in as Alice, opens the account page with a marker put on it, and leaves it for the login
  # page through a link.
  defp leave_marked_account_page(session) do
    session
    |> visit(LoginPage)
    |> log_in("Log in as Alice", "alice")
    |> click(link("Account page link"))
    |> assert_page(AccountPage)
    |> assert_text(css("#user"), "alice")
    |> put_marker()
    |> click(link("Login page link"))
    |> assert_page(LoginPage)
  end

  defp log_in(session, button_text, user) do
    session
    |> click(button(button_text))
    |> assert_text(css("#result"), "logged in as #{user}")
  end

  defp log_out(session) do
    session
    |> click(button("Log out"))
    |> assert_text(css("#result"), "logged out")
  end

  defp put_marker(session) do
    session
    |> click(button("Put marker"))
    |> assert_text(css("#marker"), "set")
  end

  describe "the user did not change" do
    feature "restores the page as it was left", %{session: session} do
      session
      |> leave_marked_account_page()
      |> go_back()
      |> assert_page(AccountPage)
      |> assert_text(css("#user"), "alice")
      |> assert_text(css("#marker"), "set")
    end

    # Writes to the session that leave the identity alone, a cart for one, don't end restores.
    feature "restores the page as it was left after a session write", %{session: session} do
      session
      |> leave_marked_account_page()
      |> click(button("Put cart item"))
      |> assert_text(css("#result"), "cart updated")
      |> go_back()
      |> assert_page(AccountPage)
      |> assert_text(css("#user"), "alice")
      |> assert_text(css("#marker"), "set")
    end

    # A page the browser loaded is stamped with the identity its document was rendered for.
    feature "restores a page left after a full page load as it was left", %{session: session} do
      session
      |> visit(LoginPage)
      |> log_in("Log in as Alice", "alice")
      |> click(link("Account page link"))
      |> assert_page(AccountPage)
      |> reload()
      |> assert_page(AccountPage)
      |> put_marker()
      |> click(link("Login page link"))
      |> assert_page(LoginPage)
      |> go_back()
      |> assert_page(AccountPage)
      |> assert_text(css("#user"), "alice")
      |> assert_text(css("#marker"), "set")
    end
  end

  describe "the user changed" do
    feature "renders the page for the user logged in now after a user switch", %{
      session: session
    } do
      session
      |> leave_marked_account_page()
      |> log_in("Log in as Bob", "bob")
      |> go_back()
      |> assert_page(AccountPage)
      |> assert_text(css("#user"), "bob")
      |> assert_text(css("#marker"), "none")
    end

    feature "renders the page for the current visitor after a logout", %{session: session} do
      session
      |> leave_marked_account_page()
      |> log_out()
      |> go_back()
      |> assert_page(AccountPage)
      |> assert_text(css("#user"), "anonymous")
      |> assert_text(css("#marker"), "none")
    end

    # The reloaded document keeps the history entries the one before it pushed, so Back reaches
    # a snapshot the earlier document took, which is restored only for the identity it was taken
    # for.
    feature "renders the page for the current visitor when Back goes past a full page load", %{
      session: session
    } do
      session
      |> leave_marked_account_page()
      |> log_out()
      |> reload()
      |> assert_page(LoginPage)
      # The document before the reload shows "logged out".
      |> assert_text(css("#result"), "none")
      |> go_back()
      |> assert_page(AccountPage)
      |> assert_text(css("#user"), "anonymous")
      |> assert_text(css("#marker"), "none")
    end

    # The page is asked for as a fresh visit asks for it, so its middleware runs.
    feature "redirects from a page that requires a login", %{session: session} do
      session
      |> visit(LoginPage)
      |> log_in("Log in as Alice", "alice")
      |> click(link("Protected page link"))
      |> assert_page(ProtectedPage)
      |> put_marker()
      |> click(link("Login page link"))
      |> assert_page(LoginPage)
      |> log_out()
      |> go_back()
      |> assert_page(LoginPage)
      # The login page that was left shows "logged out", so only a fresh one, from the redirect,
      # shows "none".
      |> assert_text(css("#result"), "none")
    end
  end

  describe "#fragment links" do
    feature "keep the page as it is when clicked", %{session: session} do
      session
      |> visit(LoginPage)
      |> log_in("Log in as Alice", "alice")
      |> click(link("Account page link"))
      |> assert_page(AccountPage)
      |> put_marker()
      |> click(link("Bottom link"))
      |> assert_script_result("return window.location.hash;", "#bottom")
      |> keep_marker()
      |> assert_page(AccountPage)
      |> assert_text(css("#user"), "alice")
      |> assert_text(css("#marker"), "set")
    end

    # The page path an entry with no id is compared with comes from the document's boot here.
    feature "keep a page the browser loaded as it is when clicked", %{session: session} do
      session
      |> visit(LoginPage)
      |> log_in("Log in as Alice", "alice")
      |> visit(AccountPage)
      |> assert_text(css("#user"), "alice")
      |> put_marker()
      |> click(link("Bottom link"))
      |> assert_script_result("return window.location.hash;", "#bottom")
      |> keep_marker()
      |> assert_page(AccountPage)
      |> assert_text(css("#marker"), "set")
    end

    feature "restore their page as it was left on Back from another page", %{session: session} do
      session
      |> visit(LoginPage)
      |> log_in("Log in as Alice", "alice")
      |> click(link("Account page link"))
      |> assert_page(AccountPage)
      |> put_marker()
      |> click(link("Bottom link"))
      |> assert_script_result("return window.location.hash;", "#bottom")
      |> click(link("Login page link"))
      |> assert_page(LoginPage)
      |> go_back()
      |> assert_page(AccountPage)
      |> assert_text(css("#user"), "alice")
      |> assert_text(css("#marker"), "set")
    end

    feature "render their page for the current visitor on Back after a logout", %{
      session: session
    } do
      session
      |> visit(LoginPage)
      |> log_in("Log in as Alice", "alice")
      |> click(link("Account page link"))
      |> assert_page(AccountPage)
      |> put_marker()
      |> click(link("Bottom link"))
      |> assert_script_result("return window.location.hash;", "#bottom")
      |> click(link("Login page link"))
      |> assert_page(LoginPage)
      |> log_out()
      |> go_back()
      |> assert_page(AccountPage)
      |> assert_text(css("#user"), "anonymous")
      |> assert_text(css("#marker"), "none")
    end
  end
end
