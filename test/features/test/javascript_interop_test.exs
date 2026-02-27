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

  describe "~JS sigil" do
    feature "DOM manipulation", %{session: session} do
      session
      |> visit(HologramFeatureTests.JavaScriptInteropPage)
      |> click(button("Run JS sigil void"))
      |> assert_text(css("#js_sigil_result"), "Hologram")
    end

    feature "return value is boxed", %{session: session} do
      session
      |> visit(HologramFeatureTests.JavaScriptInteropPage)
      |> click(button("Run JS sigil returning value"))
      |> assert_text(css("#call_result"), "{11, true}")
    end
  end

  describe "JS.call/3" do
    feature "sync method", %{session: session} do
      session
      |> visit(HologramFeatureTests.JavaScriptInteropPage)
      |> click(button("Call sync method"))
      |> assert_text(css("#call_result"), "{3, true}")
    end

    feature "callback interop", %{session: session} do
      session
      |> visit(HologramFeatureTests.JavaScriptInteropPage)
      |> click(button("Callback interop"))
      |> assert_text(css("#call_result"), "[2, 4, 6]")
    end
  end

  describe "JS.call_async/3" do
    feature "async method", %{session: session} do
      session
      |> visit(HologramFeatureTests.JavaScriptInteropPage)
      |> click(button("Call async method"))
      |> assert_text(css("#call_result"), "{30, true}")
    end

    feature "promise-returning method", %{session: session} do
      session
      |> visit(HologramFeatureTests.JavaScriptInteropPage)
      |> click(button("Call promise method"))
      |> assert_text(css("#call_result"), "{300, true}")
    end

    feature "async anonymous function call", %{session: session} do
      session
      |> visit(HologramFeatureTests.JavaScriptInteropPage)
      |> click(button("Async anonymous function call"))
      |> assert_text(css("#call_result"), "{27, true}")
    end

    feature "async apply", %{session: session} do
      session
      |> visit(HologramFeatureTests.JavaScriptInteropPage)
      |> click(button("Async apply"))
      |> assert_text(css("#call_result"), "{31, true}")
    end

    feature "async case", %{session: session} do
      session
      |> visit(HologramFeatureTests.JavaScriptInteropPage)
      |> click(button("Async case"))
      |> assert_text(css("#call_result"), ":matched")
    end

    feature "async comprehension", %{session: session} do
      session
      |> visit(HologramFeatureTests.JavaScriptInteropPage)
      |> click(button("Async comprehension"))
      |> assert_text(css("#call_result"), "[30, 60, 90]")
    end

    feature "async cond", %{session: session} do
      session
      |> visit(HologramFeatureTests.JavaScriptInteropPage)
      |> click(button("Async cond"))
      |> assert_text(css("#call_result"), ":correct")
    end

    feature "async dynamic call", %{session: session} do
      session
      |> visit(HologramFeatureTests.JavaScriptInteropPage)
      |> click(button("Async dynamic call"))
      |> assert_text(css("#call_result"), "{33, true}")
    end

    # TODO: add "async try" feature test once async try expression is fully implemented
  end

  feature "JS.delete/2", %{session: session} do
    session
    |> visit(HologramFeatureTests.JavaScriptInteropPage)
    |> click(button("Delete property"))
    |> assert_text(css("#call_result"), ~s({"undefined", true}))
  end

  feature "JS.eval/1", %{session: session} do
    session
    |> visit(HologramFeatureTests.JavaScriptInteropPage)
    |> click(button("Evaluate expression"))
    |> assert_text(css("#call_result"), "{7, true}")
  end

  feature "JS.exec/1", %{session: session} do
    session
    |> visit(HologramFeatureTests.JavaScriptInteropPage)
    |> click(button("Execute code"))
    |> assert_text(css("#call_result"), "{5, true}")
  end

  feature "JS.get/2", %{session: session} do
    session
    |> visit(HologramFeatureTests.JavaScriptInteropPage)
    |> click(button("Get property"))
    |> assert_text(css("#call_result"), "{10, true}")
  end

  feature "JS.instanceof/2", %{session: session} do
    session
    |> visit(HologramFeatureTests.JavaScriptInteropPage)
    |> click(button("Instanceof check"))
    |> assert_text(css("#call_result"), "{true, true}")
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
