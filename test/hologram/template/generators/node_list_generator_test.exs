defmodule Hologram.Template.NodeListGeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Template.Document.TextNode
  alias Hologram.Template.NodeListGenerator

  test "generate/1" do
    nodes = [
      %TextNode{content: "test_1"},
      %TextNode{content: "test_2"}
    ]

    result = NodeListGenerator.generate(nodes)
    expected = "[{ type: 'text', content: 'test_1' }, { type: 'text', content: 'test_2' }]"

    assert result == expected
  end
end
