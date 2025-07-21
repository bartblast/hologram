defmodule HologramFeatureTests.TemplateSyntaxTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.TemplateSyntax.ComponentPage
  alias HologramFeatureTests.TemplateSyntax.ForBlockPage
  alias HologramFeatureTests.TemplateSyntax.IfBlockPage
  alias HologramFeatureTests.TemplateSyntax.InterpolationPage
  alias HologramFeatureTests.TemplateSyntax.PublicCommentPage
  alias HologramFeatureTests.TemplateSyntax.RawBlockPage
  alias HologramFeatureTests.TemplateSyntax.TextAndElementPage

  describe "nodes" do
    feature "text and element", %{session: session} do
      session
      |> visit(TextAndElementPage)
      |> assert_has(css("div.parent_elem span.child_elem", text: "my text"))
    end

    feature "component", %{session: session} do
      session
      |> visit(ComponentPage)
      |> assert_has(css("div#my_component", text: "abc"))
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

  describe "if block" do
    feature "with truthy condition", %{session: session} do
      session
      |> visit(IfBlockPage)
      |> assert_has(css("#block_1", text: "abc"))
    end

    feature "with falsy condition, having else subblock", %{session: session} do
      session
      |> visit(IfBlockPage)
      |> assert_has(css("#block_2", text: "acd"))
    end

    feature "with falsy condition, not having else subblock", %{session: session} do
      session
      |> visit(IfBlockPage)
      |> assert_has(css("#block_3", text: "ac"))
    end
  end

  feature "raw block", %{session: session} do
    session
    |> visit(RawBlockPage)
    |> assert_has(css("body", text: "{%if false}abc{@var}xyz{/if}"))
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

  feature "public comment", %{session: session} do
    session
    |> visit(PublicCommentPage)
    |> assert_public_comment("my comment")
  end
end
