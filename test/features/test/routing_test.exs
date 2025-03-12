defmodule HologramFeatureTests.RoutingTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Routing.RouteWithoutParamsPage
  alias HologramFeatureTests.Routing.RouteWithParamsPage

  feature "route without params", %{session: session} do
    session
    |> visit(RouteWithoutParamsPage)
    |> assert_text(css("#page_module"), inspect(RouteWithoutParamsPage))
    |> assert_text(css("#page_params"), inspect(%{}))
  end

  feature "route with params", %{session: session} do
    session
    |> visit(RouteWithParamsPage, a: "abc", b: 123)
    |> assert_text(css("#page_module"), inspect(RouteWithParamsPage))
    |> assert_text(css("#page_params"), inspect(%{a: "abc", b: 123}))
  end
end
