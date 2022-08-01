defmodule Hologram.Template.ElementNodeTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR.{AdditionOperator, IntegerType, ModuleAttributeOperator, TupleType}
  alias Hologram.Template.VDOM.{ElementNode, Expression, TextNode}
  alias Hologram.Template.ElementNodeTransformer

  @children :children_placeholder
  @context %Context{}
  @tag_name "div"

  test "attr without modifiers" do
    attrs = [{"test_key", [literal: "test_value"]}]
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

  test "attr with modifier" do
    attrs = [{"test_key.modifier_1.modifier_2", [literal: "test_value"]}]
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

  test "boolean attr value" do
    attrs = [{"test_key", []}]
    result = ElementNodeTransformer.transform(@tag_name, @children, attrs, @context)

    expected = %ElementNode{
      tag: @tag_name,
      children: @children,
      attrs: %{
        test_key: %{
          value: [],
          modifiers: []
        }
      }
    }

    assert result == expected
  end

  test "expression attr value" do
    attrs = [{"test_key", [expression: "{1 + 2}"]}]
    result = ElementNodeTransformer.transform(@tag_name, @children, attrs, @context)

    expected = %ElementNode{
      tag: @tag_name,
      children: @children,
      attrs: %{
        test_key: %{
          value: [
            %Expression{
              ir: %TupleType{
                data: [
                  %AdditionOperator{
                    left: %IntegerType{value: 1},
                    right: %IntegerType{value: 2}
                  }
                ]
              }
            }
          ],
          modifiers: []
        }
      }
    }

    assert result == expected
  end

  test "multi-part attr value" do
    attrs = [{"test_key", [literal: "abc", expression: "{@k}", literal: "xyz"]}]
    result = ElementNodeTransformer.transform(@tag_name, @children, attrs, @context)

    expected = %ElementNode{
      tag: @tag_name,
      children: @children,
      attrs: %{
        test_key: %{
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
