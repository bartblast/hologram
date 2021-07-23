defmodule Hologram.Template.ElementNodeGeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.{StringType, TupleType}
  alias Hologram.Template.Document.{ElementNode, Expression}
  alias Hologram.Template.ElementNodeGenerator

  test "not attrs, no children" do
    attrs = %{}
    children = []

    result = ElementNodeGenerator.generate("div", attrs, children)
    expected = "{ type: 'element', tag: 'div', attrs: {}, children: [] }"

    assert result == expected
  end

  test "has attrs" do
    attrs = %{"attr_1" => "value_1", "attr_2" => "value_2"}
    children = []

    result = ElementNodeGenerator.generate("div", attrs, children)

    expected =
      "{ type: 'element', tag: 'div', attrs: { 'attr_1': 'value_1', 'attr_2': 'value_2' }, children: [] }"

    assert result == expected
  end

  test "has children" do
    attrs = %{}

    children = [
      %ElementNode{tag: "span", attrs: %{}, children: []},
      %ElementNode{tag: "h1", attrs: %{}, children: []}
    ]

    result = ElementNodeGenerator.generate("div", attrs, children)

    expected =
      "{ type: 'element', tag: 'div', attrs: {}, children: [{ type: 'element', tag: 'span', attrs: {}, children: [] }, { type: 'element', tag: 'h1', attrs: {}, children: [] }] }"

    assert result == expected
  end

  test "doesn't remove any attrs" do
    attrs = %{"on_click" => "test"}
    children = []

    result = ElementNodeGenerator.generate("div", attrs, children)
    expected = "{ type: 'element', tag: 'div', attrs: { 'on_click': 'test' }, children: [] }"

    assert result == expected
  end

  test "expression attr" do
    expr =
      %Expression{
        ir: %TupleType{
          data: [%StringType{value: "abc"}]
        }
      }

    attrs = %{"on_click" => expr}
    children = []

    result = ElementNodeGenerator.generate("div", attrs, children)

    expected = "{ type: 'element', tag: 'div', attrs: { 'on_click': { type: 'expression', callback: ($state) => { return { type: 'tuple', data: [ { type: 'string', value: 'abc' } ] } } } }, children: [] }"

    assert result == expected
  end
end
