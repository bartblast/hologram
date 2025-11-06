defmodule HologramFeatureTests.RoutingTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.Routing.RouteWithoutParamsPage
  alias HologramFeatureTests.Routing.RouteWithParamsPage

  feature "route without params", %{session: session} do
    session
    |> visit(RouteWithoutParamsPage)
    |> assert_text("Route Without Params Page")
    |> assert_text(css("#page_module"), inspect(RouteWithoutParamsPage))
    |> assert_text(css("#page_params"), inspect(%{}))
  end

  feature "route with params", %{session: session} do
    expected = inspect(%{a: "abc", b: 123})

    session
    |> visit(RouteWithParamsPage, a: "abc", b: 123)
    |> assert_text("Route With Params Page")
    |> assert_text(css("#page_module"), inspect(RouteWithParamsPage))
    |> assert_text(css("#page_params"), expected)
  end

  # Use hardcoded path with percent-encoded params to test server-side decoding.
  # Non-hardcoded call: visit(RouteWithPercentEncodedParamsPage, a: "hello world", b: "foo/bar")
  # would test the same decoding, but with encoding done by the test framework.
  # Client-side encoding is tested in navigation_test.exs.
  feature "route with percent-encoded params", %{session: session} do
    session
    |> visit("/routing/route-with-percent-encoded-params/hello%20world/foo%2Fbar")
    |> assert_text("Route With Percent Encoded Params Page")
    |> assert_text(css("#param_a"), ~s'"hello world"')
    |> assert_text(css("#param_b"), ~s'"foo/bar"')
  end
end
