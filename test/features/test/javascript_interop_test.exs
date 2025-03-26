defmodule HologramFeatureTests.JavaScriptInteropTest do
  use HologramFeatureTests.TestCase, async: true

  feature "~JS sigil", %{session: session} do
    session
    |> visit(HologramFeatureTests.JavaScriptInteropPage)
    |> click(button("Run JavaScript snippet"))
    |> assert_text(css("#result"), "Hologram")
  end
end
