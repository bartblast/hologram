defmodule Hologram.Compiler.PatternMatchDeconstructorTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.PatternMatchDeconstructor
  alias Hologram.Compiler.IR

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

  test "aggregate_bindings/1" do
    access_paths = [
      [pattern_value: %IR.IntegerType{value: 2}, tuple_index: 1],
      [binding: :a, tuple_index: 0],
      [:expression_value, {:tuple_index, 0}],
      [binding: :b, list_index: 2, list_index: 1],
      [pattern_value: %IR.IntegerType{value: 3}, tuple_index: 2],
      [binding: :a, map_key: %IR.AtomType{value: :c}, map_key: %IR.StringType{value: "b"}]
    ]

    assert aggregate_bindings(access_paths) == %{
             a: [
               [tuple_index: 0],
               [
                 map_key: %IR.StringType{value: "b"},
                 map_key: %IR.AtomType{value: :c}
               ]
             ],
             b: [[list_index: 1, list_index: 2]]
           }
  end

  describe "deconstruct/3" do
    # --- MATCH OPERATOR ---

    test "match operator, literal value on both sides" do
      # 1 = 2
      ir = %IR.MatchOperator{
        left: %IR.IntegerType{value: 1},
        right: %IR.IntegerType{value: 2}
      }

      assert deconstruct(ir) == [[pattern_value: %IR.IntegerType{value: 1}], [:expression_value]]
    end

    test "match operator, symbol in pattern" do
      # x = 2
      ir = %IR.MatchOperator{
        left: %IR.Symbol{name: :x},
        right: %IR.IntegerType{value: 2}
      }

      assert deconstruct(ir) == [[binding: :x], [:expression_value]]
    end

    test "match operator, symbol in expression" do
      # 1 = x
      ir = %IR.MatchOperator{
        left: %IR.IntegerType{value: 1},
        right: %IR.Symbol{name: :x}
      }

      assert deconstruct(ir) == [[pattern_value: %IR.IntegerType{value: 1}], [:expression_value]]
    end

    test "match operator, nested, symbol in pattern" do
      # x = 2 = 3
      ir = %IR.MatchOperator{
        left: %IR.Symbol{name: :x},
        right: %IR.MatchOperator{
          left: %IR.IntegerType{value: 2},
          right: %IR.IntegerType{value: 3}
        }
      }

      assert deconstruct(ir) == [
               [binding: :x],
               [pattern_value: %IR.IntegerType{value: 2}],
               [:expression_value]
             ]
    end

    test "match operator, nested, symbol in the middle" do
      # 1 = x = 3
      ir = %IR.MatchOperator{
        left: %IR.IntegerType{value: 1},
        right: %IR.MatchOperator{
          left: %IR.Symbol{name: :x},
          right: %IR.IntegerType{value: 3}
        }
      }

      assert deconstruct(ir) == [
               [pattern_value: %IR.IntegerType{value: 1}],
               [binding: :x],
               [:expression_value]
             ]
    end

    test "match operator, nested, symbol in expression" do
      # 1 = 2 = x
      ir = %IR.MatchOperator{
        left: %IR.IntegerType{value: 1},
        right: %IR.MatchOperator{
          left: %IR.IntegerType{value: 2},
          right: %IR.Symbol{name: :x}
        }
      }

      assert deconstruct(ir) == [
               [pattern_value: %IR.IntegerType{value: 1}],
               [pattern_value: %IR.IntegerType{value: 2}],
               [:expression_value]
             ]
    end

    test "match operator, nested multiple-times" do
      # {a = b, 2, 3} = {1, c = d, 3} = {1, 2, e = f}
      ir = %IR.MatchOperator{
        left: %IR.TupleType{
          data: [
            %IR.MatchOperator{
              left: %IR.Symbol{name: :a},
              right: %IR.Symbol{name: :b}
            },
            %IR.IntegerType{value: 2},
            %IR.IntegerType{value: 3}
          ]
        },
        right: %IR.MatchOperator{
          left: %IR.TupleType{
            data: [
              %IR.IntegerType{value: 1},
              %IR.MatchOperator{
                left: %IR.Symbol{name: :c},
                right: %IR.Symbol{name: :d}
              },
              %IR.IntegerType{value: 3}
            ]
          },
          right: %IR.TupleType{
            data: [
              %IR.IntegerType{value: 1},
              %IR.IntegerType{value: 2},
              %IR.MatchOperator{
                left: %IR.Symbol{name: :e},
                right: %IR.Symbol{name: :f}
              }
            ]
          }
        }
      }

      assert deconstruct(ir) == [
               [binding: :a, tuple_index: 0],
               [binding: :b, tuple_index: 0],
               [pattern_value: %IR.IntegerType{value: 2}, tuple_index: 1],
               [pattern_value: %IR.IntegerType{value: 3}, tuple_index: 2],
               [pattern_value: %IR.IntegerType{value: 1}, tuple_index: 0],
               [binding: :c, tuple_index: 1],
               [binding: :d, tuple_index: 1],
               [pattern_value: %IR.IntegerType{value: 3}, tuple_index: 2],
               [:expression_value, {:tuple_index, 0}],
               [:expression_value, {:tuple_index, 1}],
               [binding: :e, tuple_index: 2],
               [:expression_value, {:tuple_index, 2}]
             ]
    end

    # --- SYMBOL ---

    test "symbol in pattern" do
      # a
      ir = %IR.Symbol{name: :a}

      assert deconstruct(ir, :pattern) == [[binding: :a]]
    end

    test "symbol in expression" do
      # a
      ir = %IR.Symbol{name: :a}

      assert deconstruct(ir, :expression) == [[:expression_value]]
    end

    # --- BASIC DATA TYPES ---

    test "basic data type in pattern" do
      # 1
      ir = %IR.IntegerType{value: 1}

      assert deconstruct(ir, :pattern) == [[pattern_value: %IR.IntegerType{value: 1}]]
    end

    test "basic data type in expression" do
      # 1
      ir = %IR.IntegerType{value: 1}

      assert deconstruct(ir, :expression) == [[:expression_value]]
    end

    # --- LIST TYPE ---

    test "non-nested list, in pattern" do
      assert deconstruct(@non_nested_list, :pattern) == [
               [pattern_value: %IR.IntegerType{value: 1}, list_index: 0],
               [binding: :a, list_index: 1]
             ]
    end

    test "non-nested list, in expression" do
      assert deconstruct(@non_nested_list, :expression) == [
               [:expression_value, {:list_index, 0}],
               [:expression_value, {:list_index, 1}]
             ]
    end

    test "nested list, in pattern" do
      assert deconstruct(@nested_list, :pattern) == [
               [binding: :a, list_index: 0],
               [
                 pattern_value: %IR.IntegerType{value: 1},
                 list_index: 0,
                 list_index: 1
               ],
               [binding: :b, list_index: 1, list_index: 1]
             ]
    end

    test "nested list, in expression" do
      assert deconstruct(@nested_list, :expression) == [
               [:expression_value, {:list_index, 0}],
               [:expression_value, {:list_index, 0}, {:list_index, 1}],
               [:expression_value, {:list_index, 1}, {:list_index, 1}]
             ]
    end

    # --- MAP TYPE ---

    test "non-nested map, in pattern" do
      assert deconstruct(@non_nested_map, :pattern) == [
               [
                 pattern_value: %IR.IntegerType{value: 1},
                 map_key: %IR.AtomType{value: :a}
               ],
               [binding: :c, map_key: %IR.StringType{value: "b"}]
             ]
    end

    test "non-nested map, in expression" do
      assert deconstruct(@non_nested_map, :expression) == [
               [:expression_value, {:map_key, %IR.AtomType{value: :a}}],
               [:expression_value, {:map_key, %IR.StringType{value: "b"}}]
             ]
    end

    test "nested map, in pattern" do
      assert deconstruct(@nested_map, :pattern) == [
               [
                 pattern_value: %IR.IntegerType{value: 1},
                 map_key: %IR.AtomType{value: :a}
               ],
               [
                 pattern_value: %IR.IntegerType{value: 2},
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

    test "nested map, in expression" do
      assert deconstruct(@nested_map, :expression) == [
               [:expression_value, {:map_key, %IR.AtomType{value: :a}}],
               [
                 :expression_value,
                 {:map_key, %IR.AtomType{value: :c}},
                 {:map_key, %IR.StringType{value: "b"}}
               ],
               [
                 :expression_value,
                 {:map_key, %IR.StringType{value: "d"}},
                 {:map_key, %IR.StringType{value: "b"}}
               ]
             ]
    end

    # --- TUPLE TYPE ---

    test "non-nested tuple, in pattern" do
      assert deconstruct(@non_nested_tuple, :pattern) == [
               [pattern_value: %IR.IntegerType{value: 1}, tuple_index: 0],
               [binding: :a, tuple_index: 1]
             ]
    end

    test "non-nested tuple, in expression" do
      assert deconstruct(@non_nested_tuple, :expression) == [
               [:expression_value, {:tuple_index, 0}],
               [:expression_value, {:tuple_index, 1}]
             ]
    end

    test "nested tuple, in pattern" do
      assert deconstruct(@nested_tuple, :pattern) == [
               [binding: :a, tuple_index: 0],
               [
                 pattern_value: %IR.IntegerType{value: 1},
                 tuple_index: 0,
                 tuple_index: 1
               ],
               [binding: :b, tuple_index: 1, tuple_index: 1]
             ]
    end

    test "nested tuple, in expression" do
      assert deconstruct(@nested_tuple, :expression) == [
               [:expression_value, {:tuple_index, 0}],
               [:expression_value, {:tuple_index, 0}, {:tuple_index, 1}],
               [:expression_value, {:tuple_index, 1}, {:tuple_index, 1}]
             ]
    end

    # --- CONS OPERATOR ---

    test "non-nested cons operator with symbol in head, in pattern" do
      assert deconstruct(@ir_1, :pattern) == [
               [binding: :a, list_index: 0],
               [
                 {:pattern_value, %IR.IntegerType{value: 1}},
                 {:list_index, 0},
                 :list_tail
               ],
               [
                 {:pattern_value, %IR.IntegerType{value: 2}},
                 {:list_index, 1},
                 :list_tail
               ]
             ]
    end

    test "non-nested cons operator with symbol in head, in expression" do
      assert deconstruct(@ir_1, :expression) == [
               [:expression_value, {:list_index, 0}],
               [:expression_value, {:list_index, 0}, :list_tail],
               [:expression_value, {:list_index, 1}, :list_tail]
             ]
    end

    test "non-nested cons operator with symbol in tail, in pattern" do
      assert deconstruct(@ir_2, :pattern) == [
               [pattern_value: %IR.IntegerType{value: 1}, list_index: 0],
               [
                 {:pattern_value, %IR.IntegerType{value: 2}},
                 {:list_index, 0},
                 :list_tail
               ],
               [{:binding, :a}, {:list_index, 1}, :list_tail]
             ]
    end

    test "non-nested cons operator with symbol in tail, in expression" do
      assert deconstruct(@ir_2, :expression) == [
               [:expression_value, {:list_index, 0}],
               [:expression_value, {:list_index, 0}, :list_tail],
               [:expression_value, {:list_index, 1}, :list_tail]
             ]
    end

    test "nested cons operator, in pattern" do
      assert deconstruct(@ir_3, :pattern) == [
               [pattern_value: %IR.IntegerType{value: 1}, list_index: 0],
               [
                 {:pattern_value, %IR.IntegerType{value: 2}},
                 {:list_index, 0},
                 :list_tail
               ],
               [
                 {:pattern_value, %IR.IntegerType{value: 3}},
                 {:list_index, 0},
                 :list_tail,
                 :list_tail
               ],
               [{:binding, :a}, {:list_index, 1}, :list_tail, :list_tail]
             ]
    end

    test "nested cons operator, in expression" do
      assert deconstruct(@ir_3, :expression) == [
               [:expression_value, {:list_index, 0}],
               [:expression_value, {:list_index, 0}, :list_tail],
               [:expression_value, {:list_index, 0}, :list_tail, :list_tail],
               [:expression_value, {:list_index, 1}, :list_tail, :list_tail]
             ]
    end

    # Only side = :pattern need to be tested, since pin operators in expression sides shouldn't compile.
    test "pin operator" do
      # ^x
      ir = %IR.PinOperator{name: :my_var}

      assert deconstruct(ir, :pattern) == [[variable: :my_var]]
    end
  end
end
