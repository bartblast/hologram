defmodule Hologram.Template.ElementNodeRendererTest do
  use Hologram.TestCase, async: true

  alias Hologram.Template.ElementNodeRenderer
  alias Hologram.Template.VirtualDOM.{ElementNode, TextNode}

  setup do
    [
      state: %{}
    ]
  end

  test "render/4", %{state: state} do
    tag = "div"
    attrs = %{attr_1: "test_attr_value_1", attr_2: "test_attr_value_2"}
    children = [
      %TextNode{content: "test_text"},
      %ElementNode{attrs: %{}, children: [], tag: "span"}
    ]

    result = ElementNodeRenderer.render(tag, attrs, children, state)

    expected =
      "<div attr_1=\"test_attr_value_1\" attr_2=\"test_attr_value_2\">test_text<span></span></div>"

    assert result == expected
  end

  describe "render_attr_name/1" do
    test "mapped" do
      assert ElementNodeRenderer.render_attr_name(":click") == "holo-click"
    end

    test "not mapped" do
      assert ElementNodeRenderer.render_attr_name("test") == "test"
    end
  end
end
