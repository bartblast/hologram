defmodule Hologram.Template.NodeListRendererTest do
  use Hologram.TestCase, async: true

  alias Hologram.Template.Document.TextNode
  alias Hologram.Template.NodeListRenderer

  test "render/2" do
    nodes = [
      %TextNode{content: "test_1"},
      %TextNode{content: "test_2"}
    ]

    state = %{}

    result = NodeListRenderer.render(nodes, state)
    expected = "test_1test_2"

    assert result == expected
  end
end
