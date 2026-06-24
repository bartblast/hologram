defmodule HologramFeatureTests.MiddlewareTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Middleware.Page1
  alias HologramFeatureTests.Middleware.Page2
  alias HologramFeatureTests.Middleware.Page4
  alias HologramFeatureTests.Middleware.Page5
  alias HologramFeatureTests.Middleware.Page6

  describe "page middleware" do
    feature "enriches the server struct before rendering", %{session: session} do
      session
      |> visit(Page1)
      |> assert_text("enriched by middleware")
    end

    feature "redirects to another page", %{session: session} do
      session
      |> visit(Page2)
      |> assert_text("redirect target reached")
    end

    feature "denies the request with a terminal response", %{session: session} do
      session
      |> visit(Page4)
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
end
