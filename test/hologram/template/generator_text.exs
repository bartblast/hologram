defmodule Hologram.Template.GeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Template.VirtualDOM.{Expression, TagNode, TextNode}
  alias Hologram.Template.Generator
  alias Hologram.Compiler.IR.AtomType

  test "expression" do
    virtual_dom = %Expression{ir: %AtomType{value: "x"}}

    result = Generator.generate(virtual_dom)
    expected = "{ type: 'expression', callback: ($state) => { type: 'atom', value: 'x' } }"

    assert result == expected
  end

  describe "tag node" do
    test "not attrs, no children" do
      virtual_dom = %TagNode{tag: "div", attrs: %{}, children: []}

      result = Generator.generate(virtual_dom)
      expected = "{ type: 'tag_node', tag: 'div', attrs: {}, children: [] }"

      assert result == expected
    end

    test "has attrs" do
      virtual_dom = %TagNode{tag: "div", attrs: %{"attr_1" => "value_1", "attr_2" => "value_2"}, children: []}

      result = Generator.generate(virtual_dom)
      expected = "{ type: 'tag_node', tag: 'div', attrs: { 'attr_1': 'value_1', 'attr_2': 'value_2' }, children: [] }"

      assert result == expected
    end

    test "has children" do
      virtual_dom =
        %TagNode{tag: "div", attrs: %{}, children: [
          %TagNode{tag: "span", attrs: %{}, children: []},
          %TagNode{tag: "h1", attrs: %{}, children: []}
        ]}

      result = Generator.generate(virtual_dom)
      expected = "{ type: 'tag_node', tag: 'div', attrs: {}, children: [{ type: 'tag_node', tag: 'span', attrs: {}, children: [] }, { type: 'tag_node', tag: 'h1', attrs: {}, children: [] }] }"

      assert result == expected
    end

    test "attr name" do
      virtual_dom = %TagNode{tag: "div", attrs: %{":click" => "test"}, children: []}

      result = Generator.generate(virtual_dom)
      expected = "{ type: 'tag_node', tag: 'div', attrs: { 'holo-click': 'test' }, children: [] }"

      assert result == expected
    end
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
