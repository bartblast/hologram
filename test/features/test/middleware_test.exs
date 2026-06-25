defmodule HologramFeatureTests.MiddlewareTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Middleware.Page1
  alias HologramFeatureTests.Middleware.Page5
  alias HologramFeatureTests.Middleware.Page6
  alias HologramFeatureTests.Middleware.Page7
  alias HologramFeatureTests.Middleware.Page8

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

    feature "folds a list of steps, including a captured function", %{session: session} do
      session
      |> visit(Page5)
      |> assert_text("shared step ran / inline step")
    end
  end

  describe "command middleware" do
    feature "folds a list of steps, including a captured function", %{session: session} do
      session
      |> visit(Page6)
      |> click(css("button[id='run_command']"))
      |> assert_text(css("#result"), "shared step ran / inline step")
    end
  end

  describe "composition" do
    feature "accumulates base-module middleware ahead of the page's own", %{session: session} do
      session
      |> visit(Page7)
      |> assert_text("shared step ran / own step")
    end

    feature "runs a group middleware attached to a page", %{session: session} do
      session
      |> visit(Page8)
      |> assert_text("shared step ran / group step")
    end
  end
end
