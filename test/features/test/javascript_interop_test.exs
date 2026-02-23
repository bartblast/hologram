defmodule HologramFeatureTests.JavaScriptInteropTest do
  use HologramFeatureTests.TestCase, async: true

  describe "binding resolution" do
    feature "global", %{session: session} do
      session
      |> visit(HologramFeatureTests.JavaScriptInteropPage)
      |> click(button("Resolve global"))
      |> assert_text(css("#call_result"), "{4, true}")
    end

    feature "imported", %{session: session} do
      session
      |> visit(HologramFeatureTests.JavaScriptInteropPage)
      |> click(button("Resolve imported"))
      |> assert_text(css("#call_result"), "{3, true}")
    end

    feature "object ref", %{session: session} do
      session
      |> visit(HologramFeatureTests.JavaScriptInteropPage)
      |> click(button("Resolve object ref"))
      |> assert_text(css("#call_result"), "{15, true}")
    end
  end

  describe "JS.call/3" do
    feature "calls method with args and returns boxed result", %{session: session} do
      session
      |> visit(HologramFeatureTests.JavaScriptInteropPage)
      |> click(button("Call method"))
      |> assert_text(css("#call_result"), "{3, true}")
    end
  end

  describe "JS.get/2" do
    feature "gets property and returns boxed result", %{session: session} do
      session
      |> visit(HologramFeatureTests.JavaScriptInteropPage)
      |> click(button("Get property"))
      |> assert_text(css("#call_result"), "{10, true}")
    end
  end

  describe "JS.new/2" do
    feature "instantiates and returns object ref", %{session: session} do
      session
      |> visit(HologramFeatureTests.JavaScriptInteropPage)
      |> click(button("New instance"))
      |> assert_text(css("#call_result"), "{10, true}")
    end
  end

  feature "~JS sigil", %{session: session} do
    session
    |> visit(HologramFeatureTests.JavaScriptInteropPage)
    |> click(button("Run JavaScript snippet"))
    |> assert_text(css("#js_snippet_result"), "Hologram")
  end
end
