defmodule HologramFeatureTests.TemplateMarkupTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.TemplateMarkup.InterpolationPage
  alias HologramFeatureTests.TemplateMarkup.TextAndElementPage

  feature "text and element", %{session: session} do
    session
    |> visit(TextAndElementPage)
    |> assert_has(css("div.parent_elem span.child_elem", text: "my text"))
  end

  describe "interpolation" do
    feature "in text", %{session: session} do
      session
      |> visit(InterpolationPage)
      |> assert_has(css("span.node_1", text: "a2c"))
    end

    feature "in attribute value", %{session: session} do
      session
      |> visit(InterpolationPage)
      |> assert_has(css("span.node_2", text: "xyz"))
    end
  end
end
