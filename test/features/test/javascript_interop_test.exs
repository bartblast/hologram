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
      |> assert_text(css("#call_result"), "{12, true}")
    end

    feature "object ref", %{session: session} do
      session
      |> visit(HologramFeatureTests.JavaScriptInteropPage)
      |> click(button("Resolve object ref"))
      |> assert_text(css("#call_result"), "{15, true}")
    end
  end

  describe "JS.call_async/3" do
    feature "async function", %{session: session} do
      session
      |> visit(HologramFeatureTests.JavaScriptInteropPage)
      |> click(button("Call async method"))
      |> assert_text(css("#call_result"), "{30, true}")
    end

    feature "promise-returning function", %{session: session} do
      session
      |> visit(HologramFeatureTests.JavaScriptInteropPage)
      |> click(button("Call promise method"))
      |> assert_text(css("#call_result"), "{300, true}")
    end

    feature "async cond", %{session: session} do
      session
      |> visit(HologramFeatureTests.JavaScriptInteropPage)
      |> click(button("Async cond"))
      |> assert_text(css("#call_result"), ":correct")
    end
  end

  feature "JS.call/3", %{session: session} do
    session
    |> visit(HologramFeatureTests.JavaScriptInteropPage)
    |> click(button("Call sync method"))
    |> assert_text(css("#call_result"), "{3, true}")
  end

  feature "~JS sigil", %{session: session} do
    session
    |> visit(HologramFeatureTests.JavaScriptInteropPage)
    |> click(button("Run JavaScript snippet"))
    |> assert_text(css("#js_snippet_result"), "Hologram")
  end

  feature "JS.get/2", %{session: session} do
    session
    |> visit(HologramFeatureTests.JavaScriptInteropPage)
    |> click(button("Get property"))
    |> assert_text(css("#call_result"), "{10, true}")
  end

  feature "JS.new/2", %{session: session} do
    session
    |> visit(HologramFeatureTests.JavaScriptInteropPage)
    |> click(button("New instance"))
    |> assert_text(css("#call_result"), "{42, true}")
  end

  feature "JS.set/3", %{session: session} do
    session
    |> visit(HologramFeatureTests.JavaScriptInteropPage)
    |> click(button("Set property"))
    |> assert_text(css("#call_result"), "{20, true}")
  end

  feature "JS.typeof/1", %{session: session} do
    session
    |> visit(HologramFeatureTests.JavaScriptInteropPage)
    |> click(button("Typeof value"))
    |> assert_text(css("#call_result"), ~s("object"))
  end
end
