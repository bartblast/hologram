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
    attrs = [{:literal, "test_key", "test_value"}]
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
    attrs = [{:literal, "test_key.modifier_1.modifier_2", "test_value"}]
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

  test "boolean attrs value" do
    attrs = [{:boolean, "test_key", nil}]
    result = ElementNodeTransformer.transform(@tag_name, @children, attrs, @context)

    expected = %ElementNode{
      tag: @tag_name,
      children: @children,
      attrs: %{
        test_key: %{
          value: nil,
          modifiers: []
        }
      }
    }

    assert result == expected
  end

  test "literal attr value with embedded expression" do
    attrs = [{:literal, "test_key", "abc{@k}xyz"}]
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

  test "expression attr value" do
    attrs = [{:expression, "test_key", "1 + 2"}]
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
end
