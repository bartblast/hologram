defmodule HologramFeatureTests.GuardsTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.GuardsPage

  describe "anonymous function" do
    feature "single guard", %{session: session} do
      session
      |> visit(GuardsPage)
      |> click(button("Anonymous function - single guard"))
      |> assert_text(css("#result"), ":b")
    end

    feature "multiple guards", %{session: session} do
      session
      |> visit(GuardsPage)
      |> click(button("Anonymous function - multiple guards"))
      |> assert_text(css("#result"), ":c")
    end
  end

  describe "case expression" do
    feature "single guard", %{session: session} do
      session
      |> visit(GuardsPage)
      |> click(button("Case expression - single guard"))
      |> assert_text(css("#result"), ":b")
    end

    feature "multiple guards", %{session: session} do
      session
      |> visit(GuardsPage)
      |> click(button("Case expression - multiple guards"))
      |> assert_text(css("#result"), ":c")
    end
  end

  describe "private function" do
    feature "single guard", %{session: session} do
      session
      |> visit(GuardsPage)
      |> click(button("Private function - single guard"))
      |> assert_text(css("#result"), ":b")
    end

    feature "multiple guards", %{session: session} do
      session
      |> visit(GuardsPage)
      |> click(button("Private function - multiple guards"))
      |> assert_text(css("#result"), ":c")
    end
  end

  describe "public function" do
    feature "single guard", %{session: session} do
      session
      |> visit(GuardsPage)
      |> click(button("Public function - single guard"))
      |> assert_text(css("#result"), ":b")
    end

    feature "multiple guards", %{session: session} do
      session
      |> visit(GuardsPage)
      |> click(button("Public function - multiple guards"))
      |> assert_text(css("#result"), ":c")
    end
  end
end
