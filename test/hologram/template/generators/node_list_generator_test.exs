defmodule Hologram.Template.NodeListGeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Template.NodeListGenerator
  alias Hologram.Template.VirtualDOM.TextNode

  test "generate/2" do
    nodes = [
      %TextNode{content: "test_1"},
      %TextNode{content: "test_2"}
    ]

    state = %{}

    result = NodeListGenerator.generate(nodes, state)
    expected = "[{ type: 'text', content: 'test_1' }, { type: 'text', content: 'test_2' }]"

    assert result == expected
  end
end
