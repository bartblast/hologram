defmodule Hologram.Compiler.PatternMatchingTest do
  use Hologram.Test.UnitCase, async: true
  import Hologram.Compiler.PatternMatching
  alias Hologram.Compiler.IR

  describe "literal value" do
    test "left side" do
      ir = %IR.IntegerType{value: 1}

      assert deconstruct(ir, :left) == [[left_value: %IR.IntegerType{value: 1}]]
    end

    test "right side" do
      ir = %IR.IntegerType{value: 1}

      assert deconstruct(ir, :right) == [[:right_value]]
    end
  end

  describe "symbol" do
    test "left side" do
      ir = %IR.Symbol{name: :a}

      assert deconstruct(ir, :left) == [[binding: :a]]
    end

    test "right side" do
      ir = %IR.Symbol{name: :a}

      assert deconstruct(ir, :right) == [[:right_value]]
    end
  end

  describe "list type" do
    test "non-nested list, left side" do
      ir = %IR.ListType{
        data: [
          %IR.IntegerType{value: 1},
          %IR.Symbol{name: :a}
        ]
      }

      assert deconstruct(ir, :left) == [
               [left_value: %IR.IntegerType{value: 1}, list_index: 0],
               [binding: :a, list_index: 1]
             ]
    end

    test "non-nested list, right side" do
      ir = %IR.ListType{
        data: [
          %IR.IntegerType{value: 1},
          %IR.Symbol{name: :a}
        ]
      }

      assert deconstruct(ir, :right) == [
               [:right_value, {:list_index, 0}],
               [:right_value, {:list_index, 1}]
             ]
    end

    test "nested list, left side" do
      ir = %IR.ListType{
        data: [
          %IR.Symbol{name: :a},
          %IR.ListType{
            data: [
              %IR.IntegerType{value: 1},
              %IR.Symbol{name: :b}
            ]
          }
        ]
      }

      assert deconstruct(ir, :left) == [
               [binding: :a, list_index: 0],
               [
                 left_value: %IR.IntegerType{value: 1},
                 list_index: 0,
                 list_index: 1
               ],
               [binding: :b, list_index: 1, list_index: 1]
             ]
    end

    test "nested list, right side" do
      ir = %IR.ListType{
        data: [
          %IR.Symbol{name: :a},
          %IR.ListType{
            data: [
              %IR.IntegerType{value: 1},
              %IR.Symbol{name: :b}
            ]
          }
        ]
      }

      assert deconstruct(ir, :right) == [
               [:right_value, {:list_index, 0}],
               [:right_value, {:list_index, 0}, {:list_index, 1}],
               [:right_value, {:list_index, 1}, {:list_index, 1}]
             ]
    end
  end
end
