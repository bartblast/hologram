defmodule Hologram.Template.NodeListGeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Template.NodeListGenerator
  alias Hologram.Template.VirtualDOM.TextNode

  test "generate/2" do
    nodes = [
      %TextNode{text: "test_1"},
      %TextNode{text: "test_2"}
    ]

    state = %{}

    result = NodeListGenerator.generate(nodes, state)
    expected = "[{ type: 'text_node', text: 'test_1' }, { type: 'text_node', text: 'test_2' }]"

    assert result == expected
  end
end
