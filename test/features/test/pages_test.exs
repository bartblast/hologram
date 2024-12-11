defmodule HologramFeatureTests.PagesTest do
  use HologramFeatureTests.TestCase, async: true
  alias HologramFeatureTests.Pages.RouteWithoutParamsPage

  describe "route" do
    feature "without params", %{session: session} do
      session
      |> visit(RouteWithoutParamsPage)
      |> assert_text(css("#result"), inspect(%{}))
    end
  end
end
