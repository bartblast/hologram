defmodule Hologram.Template.Renderer.NodeListTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Template.Renderer
  alias Hologram.Template.VDOM.TextNode

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
