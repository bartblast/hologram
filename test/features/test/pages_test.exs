defmodule HologramFeatureTests.PagesTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Pages.LayoutGettingPropsExplicitelyPage
  alias HologramFeatureTests.Pages.LayoutGettingPropsImplicitelyPage
  alias HologramFeatureTests.Pages.LayoutWithoutPropsPage
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

  describe "layout" do
    feature "without props", %{session: session} do
      session
      |> visit(LayoutWithoutPropsPage)
      |> assert_text(css("#layout_result"), inspect(%{cid: "layout"}))
    end

    feature "getting props implicitely", %{session: session} do
      session
      |> visit(LayoutGettingPropsImplicitelyPage)
      |> assert_text(css("#layout_result"), inspect(%{a: "abc", b: 123, cid: "layout"}))
    end

    feature "getting props explicitely", %{session: session} do
      session
      |> visit(LayoutGettingPropsExplicitelyPage)
      |> assert_text(css("#layout_result"), inspect(%{a: "abc", b: 123, cid: "layout"}))
    end
  end
end
