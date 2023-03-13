defmodule Hologram.Template.CommonsTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR.ModuleAttributeOperator
  alias Hologram.Compiler.IR.TupleType
  alias Hologram.Template.Commons
  alias Hologram.Template.VDOM.Expression
  alias Hologram.Template.VDOM.TextNode

  describe "transform_attr_value/2" do
    test "text attribute value part" do
      value = [text: "test_text"]

      result = Commons.transform_attr_value(value, %Context{})
      expected = [%TextNode{content: "test_text"}]

      assert result == expected
    end

    test "expression attribute value part" do
      value = [expression: "{@test}"]
      result = Commons.transform_attr_value(value, %Context{})

      expected = [
        %Expression{
          ir: %TupleType{
            data: [%ModuleAttributeOperator{name: :test}]
          }
        }
      ]

      assert result == expected
    end

    test "boolean attribute value" do
      result = Commons.transform_attr_value([], %Context{})
      assert result == []
    end

    test "multiple attribute value parts" do
      value = [text: "abc", expression: "{@test}", text: "xyz"]
      result = Commons.transform_attr_value(value, %Context{})

      expected = [
        %TextNode{content: "abc"},
        %Expression{
          ir: %TupleType{
            data: [%ModuleAttributeOperator{name: :test}]
          }
        },
        %TextNode{content: "xyz"}
      ]

      assert result == expected
    end
  end
end
