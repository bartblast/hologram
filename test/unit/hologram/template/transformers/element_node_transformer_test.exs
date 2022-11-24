defmodule Hologram.Template.ElementNodeTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Context
  alias Hologram.Template.ElementNodeTransformer
  alias Hologram.Template.VDOM.ElementNode
  alias Hologram.Template.VDOM.TextNode

  @children :children_placeholder
  @context %Context{}
  @tag_name "div"

  test "attribute without modifiers" do
    attrs = [{"test_key", [text: "test_value"]}]
    result = ElementNodeTransformer.transform(@tag_name, @children, attrs, @context)

    expected = %ElementNode{
      tag: @tag_name,
      children: @children,
      attrs: %{
        test_key: %{
          value: [%TextNode{content: "test_value"}],
          modifiers: []
        }
      }
    }

    assert result == expected
  end

  test "attribute with modifier" do
    attrs = [{"test_key.modifier_1.modifier_2", [text: "test_value"]}]
    result = ElementNodeTransformer.transform(@tag_name, @children, attrs, @context)

    expected = %ElementNode{
      tag: @tag_name,
      children: @children,
      attrs: %{
        test_key: %{
          value: [%TextNode{content: "test_value"}],
          modifiers: [:modifier_1, :modifier_2]
        }
      }
    }

    assert result == expected
  end
end
