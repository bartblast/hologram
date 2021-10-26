defmodule Hologram.Template.ElementNodeTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.{ModuleAttributeOperator, TupleType}
  alias Hologram.Template.VDOM.{ElementNode, Expression, TextNode}
  alias Hologram.Template.ElementNodeTransformer

  test "attr without modifiers" do
    tag = "div"
    children = [:child_stub_1, :child_stub_2]
    attrs = [{"attr_1", "value_1"}, {"attr_2", "value_2"}]

    result = ElementNodeTransformer.transform(tag, children, attrs)

    expected = %ElementNode{
      tag: tag,
      children: children,
      attrs: %{
        attr_1: %{
          value: [%TextNode{content: "value_1"}],
          modifiers: []
        },
        attr_2: %{
          value: [%TextNode{content: "value_2"}],
          modifiers: []
        }
      }
    }

    assert result == expected
  end

  test "attr with modifier" do
    tag = "div"
    children = [:child_stub_1, :child_stub_2]
    attrs = [{"attr_1.modifier_1", "value_1"}, {"attr_2.modifier_2.modifier_3", "value_2"}]

    result = ElementNodeTransformer.transform(tag, children, attrs)

    expected = %ElementNode{
      tag: tag,
      children: children,
      attrs: %{
        attr_1: %{
          value: [%TextNode{content: "value_1"}],
          modifiers: [:modifier_1]
        },
        attr_2: %{
          value: [%TextNode{content: "value_2"}],
          modifiers: [:modifier_2, :modifier_3]
        }
      }
    }

    assert result == expected
  end

  test "attr with embedded expression" do
    tag = "div"
    children = [:child_stub_1, :child_stub_2]
    attrs = [{"attr_1", "value_1"}, {"attr_2", "abc{@k}xyz"}]

    result = ElementNodeTransformer.transform(tag, children, attrs)

    expected = %ElementNode{
      tag: tag,
      children: children,
      attrs: %{
        attr_1: %{
          value: [%TextNode{content: "value_1"}],
          modifiers: []
        },
        attr_2: %{
          value: [
            %TextNode{content: "abc"},
            %Expression{
              ir: %TupleType{
                data: [
                  %ModuleAttributeOperator{name: :k}
                ]
              }
            },
            %TextNode{content: "xyz"}
          ],
          modifiers: []
        }
      }
    }

    assert result == expected
  end
end
