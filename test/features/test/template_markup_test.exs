defmodule HologramFeatureTests.TemplateMarkupTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.TemplateMarkup.ForBlockPage
  alias HologramFeatureTests.TemplateMarkup.InterpolationPage
  alias HologramFeatureTests.TemplateMarkup.PublicCommentPage
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

  feature "for block", %{session: session} do
    session
    |> visit(ForBlockPage)
    |> assert_count(".item", 3)
    |> assert_has(css("#item_1.item", text: "text_1"))
    |> assert_has(css("#item_2.item", text: "text_2"))
    |> assert_has(css("#item_3.item", text: "text_3"))
  end

  feature "public comment", %{session: session} do
    session
    |> visit(PublicCommentPage)
    |> assert_public_comment("my comment")
  end
end
