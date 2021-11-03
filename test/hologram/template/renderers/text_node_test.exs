defmodule Hologram.Template.Renderer.TextNodeTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Template.Renderer
  alias Hologram.Template.VDOM.TextNode

  test "render/2" do
    content = "a&lcub;b&rcub;ca&lcub;b&rcub;c"
    text_node = %TextNode{content: content}

    result = Renderer.render(text_node, %{})

    expected = "a{b}ca{b}c"
    assert result == expected
  end
end
