defmodule Hologram.Template.GeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Template.VirtualDOM.{Component, ElementNode, Expression, TextNode}
  alias Hologram.Template.Generator
  alias Hologram.Compiler.IR.AtomType

  setup do
    [
      module_attributes: []
    ]
  end

  test "node list" do
    nodes = [
      %TextNode{content: "test_1"},
      %TextNode{content: "test_2"}
    ]

    state = %{}

    result = Generator.generate(nodes, state)
    expected = "[{ type: 'text', content: 'test_1' }, { type: 'text', content: 'test_2' }]"

    assert result == expected
  end

  test "component", context do
    virtual_dom = %Component{module: [:Abc, :Bcd]}

    result = Generator.generate(virtual_dom, context)
    expected = "{ type: 'component', module: 'Abc.Bcd' }"

    assert result == expected
  end

  test "element node", context do
    virtual_dom = %ElementNode{tag: "div", attrs: %{}, children: []}

    result = Generator.generate(virtual_dom, context)
    expected = "{ type: 'element', tag: 'div', attrs: {}, children: [] }"

    assert result == expected
  end

  test "expression", context do
    virtual_dom = %Expression{ir: %AtomType{value: "x"}}

    result = Generator.generate(virtual_dom, context)

    expected =
      "{ type: 'expression', callback: ($state) => { return { type: 'atom', value: 'x' } } }"

    assert result == expected
  end

  test "text node", context do
    virtual_dom = %TextNode{content: "abc"}

    result = Generator.generate(virtual_dom, context)
    expected = "{ type: 'text', content: 'abc' }"

    assert result == expected
  end
end
