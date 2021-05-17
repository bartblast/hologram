defmodule Hologram.Template.IRGeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Template.AST.{Expression, TagNode, TextNode}
  alias Hologram.Template.IRGenerator
  alias Hologram.Compiler.AST.AtomType

  test "expression" do
    ast = %Expression{ast: %AtomType{value: "x"}}

    result = IRGenerator.generate(ast)
    expected = "{ type: 'expression', callback: ($state) => { type: 'atom', value: 'x' } }"

    assert result == expected
  end

  describe "tag node" do
    test "not attrs, no children" do
      ast = %TagNode{tag: "div", attrs: %{}, children: []}

      result = IRGenerator.generate(ast)
      expected = "{ type: 'tag_node', tag: 'div', attrs: {}, children: [] }"

      assert result == expected
    end

    test "has attrs" do
      ast = %TagNode{tag: "div", attrs: %{"attr_1" => "value_1", "attr_2" => "value_2"}, children: []}

      result = IRGenerator.generate(ast)
      expected = "{ type: 'tag_node', tag: 'div', attrs: { 'attr_1': 'value_1', 'attr_2': 'value_2' }, children: [] }"

      assert result == expected
    end

    test "has children" do
      ast =
        %TagNode{tag: "div", attrs: %{}, children: [
          %TagNode{tag: "span", attrs: %{}, children: []},
          %TagNode{tag: "h1", attrs: %{}, children: []}
        ]}

      result = IRGenerator.generate(ast)
      expected = "{ type: 'tag_node', tag: 'div', attrs: {}, children: [{ type: 'tag_node', tag: 'span', attrs: {}, children: [] }, { type: 'tag_node', tag: 'h1', attrs: {}, children: [] }] }"

      assert result == expected
    end

    test "attr name" do
      ast = %TagNode{tag: "div", attrs: %{":click" => "test"}, children: []}

      result = IRGenerator.generate(ast)
      expected = "{ type: 'tag_node', tag: 'div', attrs: { 'holo-click': 'test' }, children: [] }"

      assert result == expected
    end
  end

  test "text node" do
    ast = %TextNode{text: "a'b\nc'd\ne"}

    result = IRGenerator.generate(ast)
    expected = "{ type: 'text_node', text: 'a\\'b\\nc\\'d\\ne' }"

    assert result == expected
  end

  test "multiple nodes" do
    nodes = [
      %TextNode{text: "test_1"},
      %TextNode{text: "test_2"}
    ]

    result = IRGenerator.generate(nodes)
    expected = "[{ type: 'text_node', text: 'test_1' }, { type: 'text_node', text: 'test_2' }]"

    assert result == expected
  end
end
