defmodule Hologram.Template.Evaluator.NodeListTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.{IntegerType, TupleType}
  alias Hologram.Template.Evaluator
  alias Hologram.Template.VDOM.{Expression, TextNode}

  describe "evaluate/2" do
    test "no nodes" do
      assert Evaluator.evaluate([], %{}) == ""
    end

    test "single node" do
      nodes = [
        %Expression{
          ir: %TupleType{
            data: [
              %IntegerType{value: 9}
            ]
          }
        }
      ]

      result = Evaluator.evaluate(nodes, %{})
      expected = "9"

      assert result == expected
    end

    test "multiple nodes" do
      nodes = [
        %TextNode{content: "abc"},
        %Expression{
          ir: %TupleType{
            data: [
              %IntegerType{value: 1}
            ]
          }
        },
        %TextNode{content: "kmn"},
        %Expression{
          ir: %TupleType{
            data: [
              %IntegerType{value: 9}
            ]
          }
        },
        %TextNode{content: "xyz"}
      ]

      result = Evaluator.evaluate(nodes, %{})
      expected = "abc1kmn9xyz"

      assert result == expected
    end
  end
end
