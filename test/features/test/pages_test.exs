defmodule HologramFeatureTests.PagesTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Pages.RouteWithParamsPage
  alias HologramFeatureTests.Pages.RouteWithoutParamsPage

  describe "route" do
    feature "without params", %{session: session} do
      session
      |> visit(RouteWithoutParamsPage)
      |> assert_text(css("#page_result"), inspect(%{}))
    end

    feature "with params", %{session: session} do
      session
      |> visit(RouteWithParamsPage, a: "abc", b: 123)
      |> assert_text(css("#page_result"), inspect(%{a: "abc", b: 123}))
    end
  end
end
