defmodule Hologram.Template.GeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Template.VirtualDOM.{Expression, TagNode, TextNode}
  alias Hologram.Template.Generator
  alias Hologram.Compiler.IR.AtomType

  setup do
    [
      module_attributes: []
    ]
  end

  test "node list" do
    nodes = [
      %TextNode{text: "test_1"},
      %TextNode{text: "test_2"}
    ]

    state = %{}

    result = Generator.generate(nodes, state)
    expected = "[{ type: 'text_node', text: 'test_1' }, { type: 'text_node', text: 'test_2' }]"

    assert result == expected
  end

  test "expression", context do
    virtual_dom = %Expression{ir: %AtomType{value: "x"}}

    result = Generator.generate(virtual_dom, context)
    expected = "{ type: 'expression', callback: ($state) => { return { type: 'atom', value: 'x' } } }"

    assert result == expected
  end

  test "tag node", context do
    virtual_dom = %TagNode{tag: "div", attrs: %{}, children: []}

    result = Generator.generate(virtual_dom, context)
    expected = "{ type: 'tag_node', tag: 'div', attrs: {}, children: [] }"

    assert result == expected
  end

  test "text node", context do
    virtual_dom = %TextNode{text: "abc"}

    result = Generator.generate(virtual_dom, context)
    expected = "{ type: 'text_node', text: 'abc' }"

    assert result == expected
  end
end
