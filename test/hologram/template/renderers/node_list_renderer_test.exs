defmodule Hologram.Template.NodeListRendererTest do
  use Hologram.TestCase, async: true

  alias Hologram.Template.NodeListRenderer
  alias Hologram.Template.VirtualDOM.TextNode

  test "render/2" do
    nodes = [
      %TextNode{text: "test_1"},
      %TextNode{text: "test_2"}
    ]

    state = %{}

    result = NodeListRenderer.render(nodes, state)
    expected = "test_1test_2"

    assert result == expected
  end
end
