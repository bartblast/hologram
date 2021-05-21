defmodule Hologram.Template.GeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Template.VirtualDOM.{Expression, TagNode, TextNode}
  alias Hologram.Template.Generator
  alias Hologram.Compiler.IR.AtomType

  test "expression" do
  end

  describe "tag node" do
  end

  test "text node" do
    virtual_dom = %TextNode{text: "a'b\nc'd\ne"}

    result = Generator.generate(virtual_dom)
    expected = "{ type: 'text_node', text: 'a\\'b\\nc\\'d\\ne' }"

    assert result == expected
  end

  test "multiple nodes" do
    nodes = [
      %TextNode{text: "test_1"},
      %TextNode{text: "test_2"}
    ]

    result = Generator.generate(nodes)
    expected = "[{ type: 'text_node', text: 'test_1' }, { type: 'text_node', text: 'test_2' }]"

    assert result == expected
  end
end
