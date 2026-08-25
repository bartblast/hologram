defmodule HologramFeatureTests.TemplateSyntaxTest do
  use HologramFeatureTests.TestCase, async: true

  alias HologramFeatureTests.TemplateSyntax.AttributeSpreadPage
  alias HologramFeatureTests.TemplateSyntax.ComponentPage
  alias HologramFeatureTests.TemplateSyntax.DynamicComponentBroadcastReceiverPage
  alias HologramFeatureTests.TemplateSyntax.DynamicComponentBroadcastSenderPage
  alias HologramFeatureTests.TemplateSyntax.DynamicComponentPage
  alias HologramFeatureTests.TemplateSyntax.DynamicComponentSwapPage
  alias HologramFeatureTests.TemplateSyntax.DynamicElementPage
  alias HologramFeatureTests.TemplateSyntax.ForBlockPage
  alias HologramFeatureTests.TemplateSyntax.IfBlockPage
  alias HologramFeatureTests.TemplateSyntax.InlineStylesheetPage
  alias HologramFeatureTests.TemplateSyntax.InterpolationPage
  alias HologramFeatureTests.TemplateSyntax.PropSpreadPage
  alias HologramFeatureTests.TemplateSyntax.PublicCommentPage
  alias HologramFeatureTests.TemplateSyntax.RawBlockPage
  alias HologramFeatureTests.TemplateSyntax.ScriptInterpolationPage
  alias HologramFeatureTests.TemplateSyntax.StyleInterpolationPage
  alias HologramFeatureTests.TemplateSyntax.TextAndElementPage

  @broadcast_channel :template_syntax_dynamic_component

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

    # The value is the page's, repeated here rather than read from it. Each run of the page's
    # script appends the value as read through double quotes, single quotes and backticks, so one
    # entry of three equal strings means the value arrived intact through each kind of literal and
    # the script ran once - the client rendered the same text the server wrote, and hydration
    # adopted the element. The closing tag inside the value did not end the element, or the
    # marker it carries would be set.
    feature "in script element", %{session: session} do
      value = ~s(</script><script>window.__xss = true</script> & "a" 'b' `c` ${d} e\\f\ng)

      session
      |> visit(ScriptInterpolationPage)
      |> assert_script_result("return window.__scriptInterpolation;", [[value, value, value]])
      |> assert_script_result("return window.__xss;", nil)
    end

    # The value read back out of the stylesheet is compared against the same value carried through
    # a script interpolation, which #1101 established arrives exact - so the expected value is not
    # written out a second time here. Chrome serializes a computed "content" with wrapping quotes
    # and backslash escapes, which the decode below undoes. The visibility assertion is the other
    # half: the closing tag inside the value did not end the element, or the rule it carries would
    # have hidden the div.
    feature "in style element", %{session: session} do
      decode = """
      const css = window.__styleInterpolation.content;
      const decoded = css.slice(1, -1).replace(/\\\\(.)/g, "$1");
      return decoded === window.__styleInterpolationExpected;
      """

      session
      |> visit(StyleInterpolationPage)
      |> assert_script_result(decode, true)
      |> assert_script_result("return window.__styleInterpolation.visibility;", "visible")
      |> assert_script_result(
        "return window.__styleInterpolation.text === document.getElementById('style_interpolation_sheet').textContent;",
        true
      )
    end
  end

  # The stylesheet is read at parse time, before the runtime boots, so these are the server's own
  # bytes rather than the client's repair of them. The last assertion compares that text with what
  # the element holds after hydration: equal means the client rendered the same stylesheet and the
  # boot patch adopted it instead of rewriting it.
  feature "inline stylesheet", %{session: session} do
    session
    |> visit(InlineStylesheetPage)
    |> assert_script_result("return window.__inlineStylesheet.color;", "rgb(1, 2, 3)")
    |> assert_script_result("return window.__inlineStylesheet.content;", ~s("a & b"))
    |> assert_script_result(
      "return window.__inlineStylesheet.text === document.getElementById('inline_stylesheet_sheet').textContent;",
      true
    )
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

  describe "dynamic component" do
    feature "named props", %{session: session} do
      session
      |> visit(DynamicComponentPage)
      |> assert_has(css("#scenario_1", text: "prop_1 = value_1"))
    end

    feature "spread props", %{session: session} do
      session
      |> visit(DynamicComponentPage)
      |> assert_has(css("#scenario_2", text: "prop_1 = value_2"))
    end

    feature "slot content", %{session: session} do
      session
      |> visit(DynamicComponentPage)
      |> assert_has(css("#scenario_3", text: "slot content = value_3"))
    end

    feature "module delivered from a command", %{session: session} do
      session
      |> visit(DynamicComponentPage)
      |> click(css("#scenario_4_button"))
      |> assert_has(css("#scenario_4", text: "loaded from command"))
    end

    # The component is referenced only in the sender page's command/3, so the receiver
    # page can render it only if broadcast-referenced components reach the runtime bundle.
    @sessions 2
    feature "module delivered from a broadcast to another page", %{
      sessions: [session_1, session_2]
    } do
      session_2 = visit(session_2, DynamicComponentBroadcastReceiverPage)
      wait_for_subscription(session_2, @broadcast_channel)

      session_1
      |> visit(DynamicComponentBroadcastSenderPage)
      |> click(css("#broadcast_button"))

      assert_has(session_2, css("#scenario_5", text: "delivered from broadcast"))
    end

    # The counts are incremented before each swap, so a swapped-in component showing
    # count = 0 proves the previous module's state was discarded rather than reused.
    feature "module swap under a cid resets state", %{session: session} do
      session
      |> visit(DynamicComponentSwapPage)
      |> assert_has(css("#component_7", text: "component_7 count = 0"))
      |> click(css("#component_7_button"))
      |> assert_has(css("#component_7", text: "component_7 count = 1"))
      |> click(css("#swap_button"))
      |> assert_has(css("#component_8", text: "component_8 count = 0"))
      |> click(css("#component_8_button"))
      |> assert_has(css("#component_8", text: "component_8 count = 1"))
      |> click(css("#swap_button"))
      |> assert_has(css("#component_7", text: "component_7 count = 0"))
    end
  end

  describe "dynamic element" do
    feature "tag name from state", %{session: session} do
      session
      |> visit(DynamicElementPage)
      |> assert_has(css("h2#scenario_1", text: "value_1"))
    end

    feature "event binding", %{session: session} do
      session
      |> visit(DynamicElementPage)
      |> assert_has(css("#scenario_2_result", text: "clicked? = false"))
      |> click(css("#scenario_2"))
      |> assert_has(css("#scenario_2_result", text: "clicked? = true"))
    end
  end
end
