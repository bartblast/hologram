defmodule Hologram.Template.Renderer.TextNodeTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Conn
  alias Hologram.Template.Renderer
  alias Hologram.Template.VDOM.TextNode

  test "render/4" do
    content = "a\\{b\\}ca\\{b\\}c"
    text_node = %TextNode{content: content}

    result = Renderer.render(text_node, %Conn{}, %{})
    expected = {"a{b}ca{b}c", %{}}

    assert result == expected
  end
end
