defmodule HologramFeatureTests.TemplateMarkupTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.TemplateMarkup.ComponentPage
  alias HologramFeatureTests.TemplateMarkup.ForBlockPage
  alias HologramFeatureTests.TemplateMarkup.InterpolationPage
  alias HologramFeatureTests.TemplateMarkup.PublicCommentPage
  alias HologramFeatureTests.TemplateMarkup.RawBlockPage
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

  describe "for block" do
    feature "having items", %{session: session} do
      session
      |> visit(ForBlockPage)
      |> assert_count("#block_1 .item", 3)
      |> assert_has(css("#block_1 #item_1.item", text: "text_1"))
      |> assert_has(css("#block_1 #item_2.item", text: "text_2"))
      |> assert_has(css("#block_1 #item_3.item", text: "text_3"))
    end

    feature "not having items", %{session: session} do
      session
      |> visit(ForBlockPage)
      |> assert_has(css("#block_2", text: "abcxyz"))
    end
  end

  feature "public comment", %{session: session} do
    session
    |> visit(PublicCommentPage)
    |> assert_public_comment("my comment")
  end

  feature "raw block", %{session: session} do
    session
    |> visit(RawBlockPage)
    |> assert_has(css("body", text: "{%if false}abc{@var}xyz{/if}"))
  end

  feature "component", %{session: session} do
    session
    |> visit(ComponentPage)
    |> assert_has(css("div#my_component", text: "abc"))
  end
end
