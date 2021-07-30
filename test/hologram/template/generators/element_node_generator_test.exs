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

  test "has attrs without modifiers" do
    attrs = %{"attr_1" => "value_1", "attr_2" => "value_2"}
    children = []

    result = ElementNodeGenerator.generate("div", attrs, children)

    attr_1 = "{ value: 'value_1', modifiers: [] }"
    attr_2 = "{ value: 'value_2', modifiers: [] }"
    expected =
      "{ type: 'element', tag: 'div', attrs: { 'attr_1': #{attr_1}, 'attr_2': #{attr_2} }, children: [] }"

    assert result == expected
  end

  test "has attrs with modifiers" do
    attrs = %{"attr_1.abc" => "value_1", "attr_2.bcd.cde" => "value_2"}
    children = []

    result = ElementNodeGenerator.generate("div", attrs, children)

    attr_1 = "{ value: 'value_1', modifiers: ['abc'] }"
    attr_2 = "{ value: 'value_2', modifiers: ['bcd', 'cde'] }"
    expected =
      "{ type: 'element', tag: 'div', attrs: { 'attr_1': #{attr_1}, 'attr_2': #{attr_2} }, children: [] }"

    assert result == expected
  end

  test "has children" do
    attrs = %{}

    children = [
      %ElementNode{tag: "span", attrs: %{}, children: []},
      %ElementNode{tag: "h1", attrs: %{}, children: []}
    ]

    result = ElementNodeGenerator.generate("div", attrs, children)

    child_1 = "{ type: 'element', tag: 'span', attrs: {}, children: [] }"
    child_2 = "{ type: 'element', tag: 'h1', attrs: {}, children: [] }"
    expected =
      "{ type: 'element', tag: 'div', attrs: {}, children: [#{child_1}, #{child_2}] }"

    assert result == expected
  end

  test "doesn't remove any attrs" do
    attrs = %{"on_click" => "test"}
    children = []

    result = ElementNodeGenerator.generate("div", attrs, children)

    on_click = "{ value: 'test', modifiers: [] }"
    expected = "{ type: 'element', tag: 'div', attrs: { 'on_click': #{on_click} }, children: [] }"

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

    callback = "($state) => { return { type: 'tuple', data: [ { type: 'string', value: 'abc' } ] } }"
    expected = "{ type: 'element', tag: 'div', attrs: { 'on_click': { value: { type: 'expression', callback: #{callback} }, modifiers: [] } }, children: [] }"

    assert result == expected
  end
end
