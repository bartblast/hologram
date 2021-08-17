defmodule Hologram.Template.GeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.{AtomType, TupleType}
  alias Hologram.Template.Document.{Component, ElementNode, Expression, TextNode}
  alias Hologram.Template.Generator

  test "node list" do
    nodes = [
      %TextNode{content: "test_1"},
      %TextNode{content: "test_2"}
    ]

    result = Generator.generate(nodes)
    expected = "[{ type: 'text', content: 'test_1' }, { type: 'text', content: 'test_2' }]"

    assert result == expected
  end

  test "component" do
    node = %Component{module: Hologram.Test.Fixtures.Template.Generator.Module1, children: []}

    result = Generator.generate(node)
    expected_module = "Elixir_Hologram_Test_Fixtures_Template_Generator_Module1"
    expected = "{ type: 'component', module: '#{expected_module}', children: [] }"

    assert result == expected
  end

  test "element node" do
    node = %ElementNode{tag: "div", attrs: %{}, children: []}

    result = Generator.generate(node)
    expected = "{ type: 'element', tag: 'div', attrs: {}, children: [] }"

    assert result == expected
  end

  test "expression" do
    node =
      %Expression{
        ir: %TupleType{
          data: [%AtomType{value: "x"}]
        }
      }

    result = Generator.generate(node)

    expected =
      "{ type: 'expression', callback: ($state) => { return { type: 'tuple', data: [ { type: 'atom', value: 'x' } ] } } }"

    assert result == expected
  end

  test "text node" do
    node = %TextNode{content: "abc"}

    result = Generator.generate(node)
    expected = "{ type: 'text', content: 'abc' }"

    assert result == expected
  end
end
