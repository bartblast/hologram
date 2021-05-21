defmodule Hologram.Template.TagNodeGeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Template.VirtualDOM.TagNode
  alias Hologram.Template.TagNodeGenerator

  setup do
    [
      module_attributes: []
    ]
  end

  test "not attrs, no children", context do
    tag = "div"
    attrs = %{}
    children = []

    result = TagNodeGenerator.generate(tag, attrs, children, context)
    expected = "{ type: 'tag_node', tag: 'div', attrs: {}, children: [] }"

    assert result == expected
  end

  test "has attrs", context do
    tag = "div"
    attrs = %{"attr_1" => "value_1", "attr_2" => "value_2"}
    children = []

    result = TagNodeGenerator.generate(tag, attrs, children, context)
    expected = "{ type: 'tag_node', tag: 'div', attrs: { 'attr_1': 'value_1', 'attr_2': 'value_2' }, children: [] }"

    assert result == expected
  end

  test "has children", context do
    tag = "div"
    attrs = %{}

    children = [
      %TagNode{tag: "span", attrs: %{}, children: []},
      %TagNode{tag: "h1", attrs: %{}, children: []}
    ]

    result = TagNodeGenerator.generate(tag, attrs, children, context)
    expected = "{ type: 'tag_node', tag: 'div', attrs: {}, children: [{ type: 'tag_node', tag: 'span', attrs: {}, children: [] }, { type: 'tag_node', tag: 'h1', attrs: {}, children: [] }] }"

    assert result == expected
  end

  test "attr name", context do
    tag = "div"
    attrs = %{":click" => "test"}
    children = []

    result = TagNodeGenerator.generate(tag, attrs, children, context)
    expected = "{ type: 'tag_node', tag: 'div', attrs: { 'holo-click': 'test' }, children: [] }"

    assert result == expected
  end
end
