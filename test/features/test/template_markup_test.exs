defmodule HologramFeatureTests.TemplateMarkupTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.TemplateMarkup.TextAndElementPage

  feature "text and element", %{session: session} do
    session
    |> visit(TextAndElementPage)
    |> assert_has(css("div.parent_elem span.child_elem", text: "my text"))
  end
end
