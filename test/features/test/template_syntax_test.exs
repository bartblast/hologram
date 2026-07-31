defmodule HologramFeatureTests.TemplateSyntaxTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.TemplateSyntax.AttributeSpreadPage
  alias HologramFeatureTests.TemplateSyntax.ComponentPage
  alias HologramFeatureTests.TemplateSyntax.ForBlockPage
  alias HologramFeatureTests.TemplateSyntax.IfBlockPage
  alias HologramFeatureTests.TemplateSyntax.InterpolationPage
  alias HologramFeatureTests.TemplateSyntax.PropSpreadPage
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

    feature "uses String.Chars protocol", %{session: session} do
      session
      |> visit(InterpolationPage)
      |> assert_has(css("#string_chars_protocol", text: "1.2.3"))
    end
  end

  feature "public comment", %{session: session} do
    session
    |> visit(PublicCommentPage)
    |> assert_public_comment("my comment")
  end

  describe "attribute spread" do
    feature "map value", %{session: session} do
      session
      |> visit(AttributeSpreadPage)
      |> assert_has(css("#scenario_1[title='value_1']"))
    end

    feature "keyword shorthand value", %{session: session} do
      session
      |> visit(AttributeSpreadPage)
      |> assert_has(css("#scenario_2[title='value_2']"))
    end

    feature "state value", %{session: session} do
      session
      |> visit(AttributeSpreadPage)
      |> assert_has(css("#scenario_3[title='value_3']"))
    end

    feature "nested value composes a dash-joined name", %{session: session} do
      session
      |> visit(AttributeSpreadPage)
      |> assert_has(css("#scenario_4[data-user-id='value_4']"))
    end

    feature "entry with nil value is not rendered", %{session: session} do
      session
      |> visit(AttributeSpreadPage)
      |> assert_has(css("#scenario_5[class='value_5']:not([title])"))
    end

    feature "literal attribute before the spread is overridden", %{session: session} do
      session
      |> visit(AttributeSpreadPage)
      |> assert_has(css("#scenario_6[title='value_6']"))
    end

    feature "literal attribute after the spread wins", %{session: session} do
      session
      |> visit(AttributeSpreadPage)
      |> assert_has(css("#scenario_7[title='value_7']"))
    end

    feature "later spread wins over an earlier one", %{session: session} do
      session
      |> visit(AttributeSpreadPage)
      |> assert_has(css("#scenario_8[title='value_8']"))
    end
  end

  describe "prop spread" do
    feature "map value", %{session: session} do
      session
      |> visit(PropSpreadPage)
      |> assert_has(css("#scenario_1", text: "prop_1 = value_1"))
    end

    feature "keyword shorthand value", %{session: session} do
      session
      |> visit(PropSpreadPage)
      |> assert_has(css("#scenario_2", text: "prop_1 = value_2"))
    end

    feature "state value", %{session: session} do
      session
      |> visit(PropSpreadPage)
      |> assert_has(css("#scenario_3", text: "prop_1 = value_3"))
    end

    feature "undeclared keys are filtered out", %{session: session} do
      session
      |> visit(PropSpreadPage)
      |> assert_has(css("#scenario_4", text: "prop_1 = value_4"))
    end

    feature "named prop before the spread is overridden", %{session: session} do
      session
      |> visit(PropSpreadPage)
      |> assert_has(css("#scenario_5", text: "prop_1 = value_5"))
    end

    feature "named prop after the spread wins", %{session: session} do
      session
      |> visit(PropSpreadPage)
      |> assert_has(css("#scenario_6", text: "prop_1 = value_6"))
    end

    feature "cid supplied through a spread initializes a stateful component", %{session: session} do
      session
      |> visit(PropSpreadPage)
      |> assert_has(css("#scenario_7", text: "my_state_value = value_7"))
    end

    feature "forwarding wrapper spreads its map prop onto an inner element", %{session: session} do
      session
      |> visit(PropSpreadPage)
      |> assert_has(css("#scenario_8[title='value_8']", text: "forwarded"))
    end
  end
end
