defmodule Hologram.Template.ElementNodeGeneratorTest do
  use Hologram.TestCase, async: true

  alias Hologram.Template.Document.ElementNode
  alias Hologram.Template.ElementNodeGenerator

  test "not attrs, no children" do
    tag = "div"
    attrs = %{}
    children = []

    result = ElementNodeGenerator.generate(tag, attrs, children)
    expected = "{ type: 'element', tag: 'div', attrs: {}, children: [] }"

    assert result == expected
  end

  test "has attrs" do
    tag = "div"
    attrs = %{"attr_1" => "value_1", "attr_2" => "value_2"}
    children = []

    result = ElementNodeGenerator.generate(tag, attrs, children)

    expected =
      "{ type: 'element', tag: 'div', attrs: { 'attr_1': 'value_1', 'attr_2': 'value_2' }, children: [] }"

    assert result == expected
  end

  test "has children" do
    tag = "div"
    attrs = %{}

    children = [
      %ElementNode{tag: "span", attrs: %{}, children: []},
      %ElementNode{tag: "h1", attrs: %{}, children: []}
    ]

    result = ElementNodeGenerator.generate(tag, attrs, children)

    expected =
      "{ type: 'element', tag: 'div', attrs: {}, children: [{ type: 'element', tag: 'span', attrs: {}, children: [] }, { type: 'element', tag: 'h1', attrs: {}, children: [] }] }"

    assert result == expected
  end

  test "attr name" do
    tag = "div"
    attrs = %{":click" => "test"}
    children = []

    result = ElementNodeGenerator.generate(tag, attrs, children)
    expected = "{ type: 'element', tag: 'div', attrs: { 'holo-click': 'test' }, children: [] }"

    assert result == expected
  end
end
