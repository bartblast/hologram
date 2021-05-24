defmodule Hologram.Template.ElementNodeGeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Template.ElementNodeGenerator
  alias Hologram.Template.VirtualDOM.ElementNode

  setup do
    [
      module_attributes: []
    ]
  end

  test "not attrs, no children", context do
    tag = "div"
    attrs = %{}
    children = []

    result = ElementNodeGenerator.generate(tag, attrs, children, context)
    expected = "{ type: 'element', tag: 'div', attrs: {}, children: [] }"

    assert result == expected
  end

  test "has attrs", context do
    tag = "div"
    attrs = %{"attr_1" => "value_1", "attr_2" => "value_2"}
    children = []

    result = ElementNodeGenerator.generate(tag, attrs, children, context)
    expected = "{ type: 'element', tag: 'div', attrs: { 'attr_1': 'value_1', 'attr_2': 'value_2' }, children: [] }"

    assert result == expected
  end

  test "has children", context do
    tag = "div"
    attrs = %{}

    children = [
      %ElementNode{tag: "span", attrs: %{}, children: []},
      %ElementNode{tag: "h1", attrs: %{}, children: []}
    ]

    result = ElementNodeGenerator.generate(tag, attrs, children, context)
    expected = "{ type: 'element', tag: 'div', attrs: {}, children: [{ type: 'element', tag: 'span', attrs: {}, children: [] }, { type: 'element', tag: 'h1', attrs: {}, children: [] }] }"

    assert result == expected
  end

  test "attr name", context do
    tag = "div"
    attrs = %{":click" => "test"}
    children = []

    result = ElementNodeGenerator.generate(tag, attrs, children, context)
    expected = "{ type: 'element', tag: 'div', attrs: { 'holo-click': 'test' }, children: [] }"

    assert result == expected
  end
end
