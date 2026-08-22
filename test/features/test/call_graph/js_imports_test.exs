defmodule HologramFeatureTests.JsImportsTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.CallGraph.JsImportsPage

  feature "js_import of a runtime-bundled component resolves", %{session: session} do
    session
    |> visit(JsImportsPage)
    |> assert_text(css("#js_call_result"), "not called yet")
    |> click(button("Call JS"))
    |> assert_text(css("#js_call_result"), "IT WORKS")
  end
end
