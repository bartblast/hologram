defmodule HologramFeatureTests.MiddlewareTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Middleware.Page1
  alias HologramFeatureTests.Middleware.Page3
  alias HologramFeatureTests.Middleware.Page5
  alias HologramFeatureTests.Middleware.Page6
  alias HologramFeatureTests.Middleware.Page7
  alias HologramFeatureTests.Middleware.Page8
  alias HologramFeatureTests.Middleware.Page9

  describe "page middleware" do
    feature "enriches the server struct before rendering", %{session: session} do
      session
      |> visit(Page1)
      |> assert_text("enriched by middleware")
    end

    # Visit by explicit path: a redirect mounts a different page, so the page-module
    # form of visit would wait for this page to mount (it never does) until it times out.
    feature "redirects to another page", %{session: session} do
      session
      |> visit("/middleware/2")
      |> assert_text("redirect target reached")
    end

    # Visit by explicit path: a terminal deny response mounts no client runtime, so the
    # page-module form of visit would hang waiting for one until it times out.
    feature "denies the request with a terminal response", %{session: session} do
      session
      |> visit("/middleware/4")
      |> assert_text("access forbidden by middleware")
    end

    feature "folds a module and a function middleware", %{session: session} do
      session
      |> visit(Page5)
      |> assert_text("shared middleware ran / inline middleware")
    end
  end

  describe "middleware redirects reached by navigating" do
    # A navigation is answered with a description of the page, so a redirect has to be described
    # too. Before that, the client followed it inside the fetch: the target's content rendered, but
    # under the clicked page's path.
    feature "lands on the target, with the target's path", %{session: session} do
      session
      |> visit(Page9)
      |> assert_text(css("#result"), "navigation origin")
      |> click(link("Redirecting link"))
      |> assert_page(Page3)
      |> assert_text(css("#result"), "redirect target reached")
    end

    feature "does not reload the document", %{session: session} do
      session
      |> visit(Page9)
      |> assert_text(css("#result"), "navigation origin")
      # The origin's inline script counts its own runs, and a document load would run it again.
      |> assert_script_result("return window.__documentLoads;", 1)
      |> click(link("Redirecting link"))
      |> assert_page(Page3)
      |> assert_script_result("return window.__documentLoads;", 1)
    end

    # The pages passed through on the way are not places to go back to, which is how a browser
    # treats a redirect chain of its own.
    feature "leaves one history entry, holding the target", %{session: session} do
      session
      |> visit(Page9)
      |> assert_text(css("#result"), "navigation origin")
      |> click(link("Redirecting link"))
      |> assert_page(Page3)
      |> go_back()
      |> assert_page(Page9)
      |> assert_text(css("#result"), "navigation origin")
    end

    feature "follows a redirect to a page that redirects again", %{session: session} do
      session
      |> visit(Page9)
      |> assert_text(css("#result"), "navigation origin")
      |> click(link("Redirect chain link"))
      |> assert_page(Page3)
      |> assert_text(css("#result"), "redirect target reached")
    end

    # A target no page owns is one only the browser can reach, so this one does load the document.
    feature "hands a target outside the app to the browser", %{session: session} do
      session
      |> visit(Page9)
      |> assert_text(css("#result"), "navigation origin")
      |> click(link("Non-page redirect link"))
      |> assert_text("pong")
    end

    # A denial is a dead end rather than a navigation, so the browser answers it and shows what a
    # typed-in URL would have shown.
    feature "hands a denying middleware's response to the browser", %{session: session} do
      session
      |> visit(Page9)
      |> assert_text(css("#result"), "navigation origin")
      |> click(link("Denied link"))
      |> assert_text("access forbidden by middleware")
    end
  end

  describe "command middleware" do
    feature "folds a module and a function middleware", %{session: session} do
      session
      |> visit(Page6)
      |> click(css("button[id='run_command']"))
      |> assert_text(css("#result"), "shared middleware ran / inline middleware")
    end
  end

  describe "composition" do
    feature "accumulates base-module middleware ahead of the page's own", %{session: session} do
      session
      |> visit(Page7)
      |> assert_text("shared middleware ran / own middleware")
    end

    feature "runs a composite middleware attached to a page", %{session: session} do
      session
      |> visit(Page8)
      |> assert_text("shared middleware ran / nested middleware")
    end
  end
end
