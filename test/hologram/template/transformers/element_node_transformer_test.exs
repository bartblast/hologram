defmodule Hologram.Template.ElementNodeTransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Template.Document.ElementNode
  alias Hologram.Template.ElementNodeTransformer

  test "attrs without modifiers" do
    tag = "div"
    children = [:child_stub_1, :child_stub_2]
    attrs = [{"attr_1", "value_1"}, {"attr_2", "value_2"}]

    result = ElementNodeTransformer.transform(tag, children, attrs)

    expected =
      %ElementNode{
        tag: tag,
        children: children,
        attrs: %{
          attr_1: %{value: "value_1", modifiers: []},
          attr_2: %{value: "value_2", modifiers: []}
        }
      }

    assert result == expected
  end

  test "attrs with modifiers" do
    tag = "div"
    children = [:child_stub_1, :child_stub_2]
    attrs = [{"attr_1.modifier_1", "value_1"}, {"attr_2.modifier_2.modifier_3", "value_2"}]

    result = ElementNodeTransformer.transform(tag, children, attrs)

    expected =
      %ElementNode{
        tag: tag,
        children: children,
        attrs: %{
          attr_1: %{value: "value_1", modifiers: [:modifier_1]},
          attr_2: %{value: "value_2", modifiers: [:modifier_2, :modifier_3]}
        }
      }

    assert result == expected
  end
end
