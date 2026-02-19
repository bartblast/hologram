defmodule HologramFeatureTests.JavaScriptInteropTest do
  use HologramFeatureTests.TestCase, async: true

  describe "JS.call/3" do
    feature "global fun", %{session: session} do
      session
      |> visit(HologramFeatureTests.JavaScriptInteropPage)
      |> click(button("Call global fun"))
      |> assert_text(css("#call_result"), "{4, true}")
    end
  end

  feature "~JS sigil", %{session: session} do
    session
    |> visit(HologramFeatureTests.JavaScriptInteropPage)
    |> click(button("Run JavaScript snippet"))
    |> assert_text(css("#js_snippet_result"), "Hologram")
  end
end
