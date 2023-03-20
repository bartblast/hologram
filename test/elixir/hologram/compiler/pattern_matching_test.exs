defmodule Hologram.Compiler.PatternMatchingTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.PatternMatching
  alias Hologram.Compiler.IR

  # describe "match operator" do
  #   test "root" do
  #     code = "{1, a} = {b, 2}"
  #     Hologram.Compiler.Reflection.ir(code) |> IO.inspect()
  #   end
  # end

  describe "literal value" do
    test "left hand side" do
      # 1
      ir = %IR.IntegerType{value: 1}

      assert deconstruct(ir, :lhs) == [[lhs_value: %IR.IntegerType{value: 1}]]
    end

    test "right hand side" do
      # 1
      ir = %IR.IntegerType{value: 1}

      assert deconstruct(ir, :rhs) == [[:rhs_value]]
    end
  end

  describe "symbol" do
    test "left hand side" do
      # a
      ir = %IR.Symbol{name: :a}

      assert deconstruct(ir, :lhs) == [[binding: :a]]
    end

    test "right hand side" do
      # a
      ir = %IR.Symbol{name: :a}

      assert deconstruct(ir, :rhs) == [[:rhs_value]]
    end
  end

  describe "cons operator" do
    # [a | [1, 2]]
    @ir_1 %IR.ConsOperator{
      head: %IR.Symbol{name: :a},
      tail: %IR.ListType{
        data: [
          %IR.IntegerType{value: 1},
          %IR.IntegerType{value: 2}
        ]
      }
    }

    # [1 | [2, a]]
    @ir_2 %IR.ConsOperator{
      head: %IR.IntegerType{value: 1},
      tail: %IR.ListType{
        data: [
          %IR.IntegerType{value: 2},
          %IR.Symbol{name: :a}
        ]
      }
    }

    # [1 | [2 | [3, a]]]
    @ir_3 %IR.ConsOperator{
      head: %IR.IntegerType{value: 1},
      tail: %IR.ConsOperator{
        head: %IR.IntegerType{value: 2},
        tail: %IR.ListType{
          data: [
            %IR.IntegerType{value: 3},
            %IR.Symbol{name: :a}
          ]
        }
      }
    }

    test "non-nested cons operator with symbol in head, left hand side" do
      assert deconstruct(@ir_1, :lhs) == [
               [binding: :a, list_index: 0],
               [
                 {:lhs_value, %IR.IntegerType{value: 1}},
                 {:list_index, 0},
                 :list_tail
               ],
               [
                 {:lhs_value, %IR.IntegerType{value: 2}},
                 {:list_index, 1},
                 :list_tail
               ]
             ]
    end

    test "non-nested cons operator with symbol in head, right hand side" do
      assert deconstruct(@ir_1, :rhs) == [
               [:rhs_value, {:list_index, 0}],
               [:rhs_value, {:list_index, 0}, :list_tail],
               [:rhs_value, {:list_index, 1}, :list_tail]
             ]
    end

    test "non-nested cons operator with symbol in tail, left hand side" do
      assert deconstruct(@ir_2, :lhs) == [
               [lhs_value: %IR.IntegerType{value: 1}, list_index: 0],
               [
                 {:lhs_value, %IR.IntegerType{value: 2}},
                 {:list_index, 0},
                 :list_tail
               ],
               [{:binding, :a}, {:list_index, 1}, :list_tail]
             ]
    end

    test "non-nested cons operator with symbol in tail, right hand side" do
      assert deconstruct(@ir_2, :rhs) == [
               [:rhs_value, {:list_index, 0}],
               [:rhs_value, {:list_index, 0}, :list_tail],
               [:rhs_value, {:list_index, 1}, :list_tail]
             ]
    end

    test "nested cons operator, left hand side" do
      assert deconstruct(@ir_3, :lhs) == [
               [lhs_value: %IR.IntegerType{value: 1}, list_index: 0],
               [
                 {:lhs_value, %IR.IntegerType{value: 2}},
                 {:list_index, 0},
                 :list_tail
               ],
               [
                 {:lhs_value, %IR.IntegerType{value: 3}},
                 {:list_index, 0},
                 :list_tail,
                 :list_tail
               ],
               [{:binding, :a}, {:list_index, 1}, :list_tail, :list_tail]
             ]
    end

    test "nested cons operator, right hand side" do
      assert deconstruct(@ir_3, :rhs) == [
               [:rhs_value, {:list_index, 0}],
               [:rhs_value, {:list_index, 0}, :list_tail],
               [:rhs_value, {:list_index, 0}, :list_tail, :list_tail],
               [:rhs_value, {:list_index, 1}, :list_tail, :list_tail]
             ]
    end
  end

  describe "list type" do
    # [1, a]
    @non_nested_list %IR.ListType{
      data: [
        %IR.IntegerType{value: 1},
        %IR.Symbol{name: :a}
      ]
    }

    # [a, [1, b]]
    @nested_list %IR.ListType{
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

    test "non-nested list, left hand side" do
      assert deconstruct(@non_nested_list, :lhs) == [
               [lhs_value: %IR.IntegerType{value: 1}, list_index: 0],
               [binding: :a, list_index: 1]
             ]
    end

    test "non-nested list, right hand side" do
      assert deconstruct(@non_nested_list, :rhs) == [
               [:rhs_value, {:list_index, 0}],
               [:rhs_value, {:list_index, 1}]
             ]
    end

    test "nested list, left hand side" do
      assert deconstruct(@nested_list, :lhs) == [
               [binding: :a, list_index: 0],
               [
                 lhs_value: %IR.IntegerType{value: 1},
                 list_index: 0,
                 list_index: 1
               ],
               [binding: :b, list_index: 1, list_index: 1]
             ]
    end

    test "nested list, right hand side" do
      assert deconstruct(@nested_list, :rhs) == [
               [:rhs_value, {:list_index, 0}],
               [:rhs_value, {:list_index, 0}, {:list_index, 1}],
               [:rhs_value, {:list_index, 1}, {:list_index, 1}]
             ]
    end
  end

  describe "map type" do
    # %{:a => 1, "b" => c}
    @non_nested_map %IR.MapType{
      data: [
        {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
        {%IR.StringType{value: "b"}, %IR.Symbol{name: :c}}
      ]
    }

    # %{:a => 1, "b" => %{:c => 2, "d" => e}}
    @nested_map %IR.MapType{
      data: [
        {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
        {%IR.StringType{value: "b"},
         %IR.MapType{
           data: [
             {%IR.AtomType{value: :c}, %IR.IntegerType{value: 2}},
             {%IR.StringType{value: "d"}, %IR.Symbol{name: :e}}
           ]
         }}
      ]
    }

    test "non-nested map, left hand side" do
      assert deconstruct(@non_nested_map, :lhs) == [
               [
                 lhs_value: %IR.IntegerType{value: 1},
                 map_key: %IR.AtomType{value: :a}
               ],
               [binding: :c, map_key: %IR.StringType{value: "b"}]
             ]
    end

    test "non-nested map, right hand side" do
      assert deconstruct(@non_nested_map, :rhs) == [
               [:rhs_value, {:map_key, %IR.AtomType{value: :a}}],
               [:rhs_value, {:map_key, %IR.StringType{value: "b"}}]
             ]
    end

    test "nested map, left hand side" do
      assert deconstruct(@nested_map, :lhs) == [
               [
                 lhs_value: %IR.IntegerType{value: 1},
                 map_key: %IR.AtomType{value: :a}
               ],
               [
                 lhs_value: %IR.IntegerType{value: 2},
                 map_key: %IR.AtomType{value: :c},
                 map_key: %IR.StringType{value: "b"}
               ],
               [
                 binding: :e,
                 map_key: %IR.StringType{value: "d"},
                 map_key: %IR.StringType{value: "b"}
               ]
             ]
    end

    test "nested map, right hand side" do
      assert deconstruct(@nested_map, :rhs) == [
               [:rhs_value, {:map_key, %IR.AtomType{value: :a}}],
               [
                 :rhs_value,
                 {:map_key, %IR.AtomType{value: :c}},
                 {:map_key, %IR.StringType{value: "b"}}
               ],
               [
                 :rhs_value,
                 {:map_key, %IR.StringType{value: "d"}},
                 {:map_key, %IR.StringType{value: "b"}}
               ]
             ]
    end
  end

  describe "tuple type" do
    # {1, a}
    @non_nested_tuple %IR.TupleType{
      data: [
        %IR.IntegerType{value: 1},
        %IR.Symbol{name: :a}
      ]
    }

    # {a, {1, b}}
    @nested_tuple %IR.TupleType{
      data: [
        %IR.Symbol{name: :a},
        %IR.TupleType{
          data: [
            %IR.IntegerType{value: 1},
            %IR.Symbol{name: :b}
          ]
        }
      ]
    }

    test "non-nested tuple, left hand side" do
      assert deconstruct(@non_nested_tuple, :lhs) == [
               [lhs_value: %IR.IntegerType{value: 1}, tuple_index: 0],
               [binding: :a, tuple_index: 1]
             ]
    end

    test "non-nested tuple, right hand side" do
      assert deconstruct(@non_nested_tuple, :rhs) == [
               [:rhs_value, {:tuple_index, 0}],
               [:rhs_value, {:tuple_index, 1}]
             ]
    end

    test "nested tuple, left hand side" do
      assert deconstruct(@nested_tuple, :lhs) == [
               [binding: :a, tuple_index: 0],
               [
                 lhs_value: %IR.IntegerType{value: 1},
                 tuple_index: 0,
                 tuple_index: 1
               ],
               [binding: :b, tuple_index: 1, tuple_index: 1]
             ]
    end

    test "nested tuple, right hand side" do
      assert deconstruct(@nested_tuple, :rhs) == [
               [:rhs_value, {:tuple_index, 0}],
               [:rhs_value, {:tuple_index, 0}, {:tuple_index, 1}],
               [:rhs_value, {:tuple_index, 1}, {:tuple_index, 1}]
             ]
    end
  end
end
