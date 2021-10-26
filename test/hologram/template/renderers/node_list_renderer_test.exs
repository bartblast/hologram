defmodule Hologram.Template.NodeListRendererTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Template.VDOM.TextNode
  alias Hologram.Template.Renderer

  test "render/2" do
    nodes = [
      %TextNode{content: "test_1"},
      %TextNode{content: "test_2"}
    ]

    result = Renderer.render(nodes, %{})
    expected = "test_1test_2"

    assert result == expected
  end
end
