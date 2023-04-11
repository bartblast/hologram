defmodule Hologram.Compiler.PatternMatchingTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.PatternMatching

  alias Hologram.Compiler.IR
  alias Hologram.Test.Fixtures.Compiler.PatternMatching.Module1

  # <<1, 2.0, 3>>
  @bitstring %IR.BitstringType{
    segments: [
      %IR.BitstringSegment{
        endianness: :big,
        signedness: :unsigned,
        size: %IR.IntegerType{value: 8},
        type: :integer,
        unit: 1,
        value: %IR.IntegerType{value: 1}
      },
      %IR.BitstringSegment{
        endianness: :big,
        signedness: :unsigned,
        size: %IR.IntegerType{value: 64},
        type: :float,
        unit: 1,
        value: %IR.FloatType{value: 2.0}
      },
      %IR.BitstringSegment{
        endianness: :big,
        signedness: :unsigned,
        size: %IR.IntegerType{value: 8},
        type: :integer,
        unit: 1,
        value: %IR.IntegerType{value: 3}
      }
    ]
  }

  # [a | [1, 2]]
  @ir_1 %IR.ConsOperator{
    head: %IR.Variable{name: :a},
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
        %IR.Variable{name: :a}
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
          %IR.Variable{name: :a}
        ]
      }
    }
  }

  # [1, a]
  @non_nested_list %IR.ListType{
    data: [
      %IR.IntegerType{value: 1},
      %IR.Variable{name: :a}
    ]
  }

  # [a, [1, b]]
  @nested_list %IR.ListType{
    data: [
      %IR.Variable{name: :a},
      %IR.ListType{
        data: [
          %IR.IntegerType{value: 1},
          %IR.Variable{name: :b}
        ]
      }
    ]
  }

  # %{:a => 1, 2.34 => c}
  @non_nested_map %IR.MapType{
    data: [
      {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
      {%IR.FloatType{value: 2.34}, %IR.Variable{name: :c}}
    ]
  }

  # %{:a => 1, 2.34 => %{:c => 2, 4.56 => e}}
  @nested_map %IR.MapType{
    data: [
      {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
      {%IR.FloatType{value: 2.34},
       %IR.MapType{
         data: [
           {%IR.AtomType{value: :c}, %IR.IntegerType{value: 2}},
           {%IR.FloatType{value: 4.56}, %IR.Variable{name: :e}}
         ]
       }}
    ]
  }

  # {1, a}
  @non_nested_tuple %IR.TupleType{
    data: [
      %IR.IntegerType{value: 1},
      %IR.Variable{name: :a}
    ]
  }

  # {a, {1, b}}
  @nested_tuple %IR.TupleType{
    data: [
      %IR.Variable{name: :a},
      %IR.TupleType{
        data: [
          %IR.IntegerType{value: 1},
          %IR.Variable{name: :b}
        ]
      }
    ]
  }

  # [{a, 1, %{b: b, c: _c, d: 2}, b} | [_e, f]] = [my_var, 3, 4]
  @reversed_access_paths [
    [binding: :a, tuple_index: 0, list_index: 0],
    [
      pattern_value: %IR.IntegerType{value: 1},
      tuple_index: 1,
      list_index: 0
    ],
    [
      binding: :b,
      map_key: %IR.AtomType{value: :b},
      tuple_index: 2,
      list_index: 0
    ],
    [
      :match_placeholder,
      {:map_key, %IR.AtomType{value: :c}},
      {:tuple_index, 2},
      {:list_index, 0}
    ],
    [
      pattern_value: %IR.IntegerType{value: 2},
      map_key: %IR.AtomType{value: :d},
      tuple_index: 2,
      list_index: 0
    ],
    [binding: :b, tuple_index: 3, list_index: 0],
    [:match_placeholder, {:list_index, 0}, :list_tail],
    [{:binding, :f}, {:list_index, 1}, :list_tail],
    [:expression_value, {:list_index, 0}],
    [:expression_value, {:list_index, 1}],
    [:expression_value, {:list_index, 2}]
  ]

  test "aggregate_bindings/1" do
    assert aggregate_bindings(@reversed_access_paths) == %{
             a: [[list_index: 0, tuple_index: 0]],
             b: [
               [
                 list_index: 0,
                 tuple_index: 2,
                 map_key: %IR.AtomType{value: :b}
               ],
               [list_index: 0, tuple_index: 3]
             ],
             f: [[:list_tail, {:list_index, 1}]]
           }
  end

  test "aggregate_pattern_values/1" do
    assert aggregate_pattern_values(@reversed_access_paths) == [
             [{:list_index, 0}, {:tuple_index, 1}, %IR.IntegerType{value: 1}],
             [
               {:list_index, 0},
               {:tuple_index, 2},
               {:map_key, %IR.AtomType{value: :d}},
               %IR.IntegerType{value: 2}
             ]
           ]
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

    test "match operator, variable in pattern" do
      # x = 2
      ir = %IR.MatchOperator{
        left: %IR.Variable{name: :x},
        right: %IR.IntegerType{value: 2}
      }

      assert deconstruct(ir) == [[binding: :x], [:expression_value]]
    end

    test "match operator, variable in expression" do
      # 1 = x
      ir = %IR.MatchOperator{
        left: %IR.IntegerType{value: 1},
        right: %IR.Variable{name: :x}
      }

      assert deconstruct(ir) == [[pattern_value: %IR.IntegerType{value: 1}], [:expression_value]]
    end

    test "match operator, nested, variable in pattern" do
      # x = 2 = 3
      ir = %IR.MatchOperator{
        left: %IR.Variable{name: :x},
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

    test "match operator, nested, variable in the middle" do
      # 1 = x = 3
      ir = %IR.MatchOperator{
        left: %IR.IntegerType{value: 1},
        right: %IR.MatchOperator{
          left: %IR.Variable{name: :x},
          right: %IR.IntegerType{value: 3}
        }
      }

      assert deconstruct(ir) == [
               [pattern_value: %IR.IntegerType{value: 1}],
               [binding: :x],
               [:expression_value]
             ]
    end

    test "match operator, nested, variable in expression" do
      # 1 = 2 = x
      ir = %IR.MatchOperator{
        left: %IR.IntegerType{value: 1},
        right: %IR.MatchOperator{
          left: %IR.IntegerType{value: 2},
          right: %IR.Variable{name: :x}
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
              left: %IR.Variable{name: :a},
              right: %IR.Variable{name: :b}
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
                left: %IR.Variable{name: :c},
                right: %IR.Variable{name: :d}
              },
              %IR.IntegerType{value: 3}
            ]
          },
          right: %IR.TupleType{
            data: [
              %IR.IntegerType{value: 1},
              %IR.IntegerType{value: 2},
              %IR.MatchOperator{
                left: %IR.Variable{name: :e},
                right: %IR.Variable{name: :f}
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

    # --- VARIABLE ---

    test "variable in pattern" do
      # a
      ir = %IR.Variable{name: :a}

      assert deconstruct(ir, :pattern) == [[binding: :a]]
    end

    test "variable in expression" do
      # a
      ir = %IR.Variable{name: :a}

      assert deconstruct(ir, :expression) == [[:expression_value]]
    end

    # Only match placeholders on pattern side need to be tested,
    # since match placeholders on expression side shouldn't compile.
    test "match placeholder in pattern" do
      # _a
      ir = %IR.MatchPlaceholder{}

      assert deconstruct(ir, :pattern) == [[:match_placeholder]]
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
               [binding: :c, map_key: %IR.FloatType{value: 2.34}]
             ]
    end

    test "non-nested map, in expression" do
      assert deconstruct(@non_nested_map, :expression) == [
               [:expression_value, {:map_key, %IR.AtomType{value: :a}}],
               [:expression_value, {:map_key, %IR.FloatType{value: 2.34}}]
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
                 map_key: %IR.FloatType{value: 2.34}
               ],
               [
                 binding: :e,
                 map_key: %IR.FloatType{value: 4.56},
                 map_key: %IR.FloatType{value: 2.34}
               ]
             ]
    end

    test "nested map, in expression" do
      assert deconstruct(@nested_map, :expression) == [
               [:expression_value, {:map_key, %IR.AtomType{value: :a}}],
               [
                 :expression_value,
                 {:map_key, %IR.AtomType{value: :c}},
                 {:map_key, %IR.FloatType{value: 2.34}}
               ],
               [
                 :expression_value,
                 {:map_key, %IR.FloatType{value: 4.56}},
                 {:map_key, %IR.FloatType{value: 2.34}}
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

    # --- BITSTRING TYPE ---

    test "bitstring in pattern" do
      assert deconstruct(@bitstring, :pattern) == [
               [
                 pattern_value: %IR.IntegerType{value: 1},
                 bitstring_segment: %{
                   endianness: :big,
                   offset: [],
                   signedness: :unsigned,
                   size: %IR.IntegerType{value: 8},
                   type: :integer,
                   unit: 1
                 }
               ],
               [
                 pattern_value: %IR.FloatType{value: 2.0},
                 bitstring_segment: %{
                   endianness: :big,
                   offset: [{%IR.IntegerType{value: 8}, 1}],
                   signedness: :unsigned,
                   size: %IR.IntegerType{value: 64},
                   type: :float,
                   unit: 1
                 }
               ],
               [
                 pattern_value: %IR.IntegerType{value: 3},
                 bitstring_segment: %{
                   endianness: :big,
                   offset: [
                     {%IR.IntegerType{value: 64}, 1},
                     {%IR.IntegerType{value: 8}, 1}
                   ],
                   signedness: :unsigned,
                   size: %IR.IntegerType{value: 8},
                   type: :integer,
                   unit: 1
                 }
               ]
             ]
    end

    test "bitstring in expression" do
      assert deconstruct(@bitstring, :expression) == [
               [
                 :expression_value,
                 {:bitstring_segment,
                  %{
                    endianness: :big,
                    offset: [],
                    signedness: :unsigned,
                    size: %IR.IntegerType{value: 8},
                    type: :integer,
                    unit: 1
                  }}
               ],
               [
                 :expression_value,
                 {:bitstring_segment,
                  %{
                    endianness: :big,
                    offset: [{%IR.IntegerType{value: 8}, 1}],
                    signedness: :unsigned,
                    size: %IR.IntegerType{value: 64},
                    type: :float,
                    unit: 1
                  }}
               ],
               [
                 :expression_value,
                 {:bitstring_segment,
                  %{
                    endianness: :big,
                    offset: [
                      {%IR.IntegerType{value: 64}, 1},
                      {%IR.IntegerType{value: 8}, 1}
                    ],
                    signedness: :unsigned,
                    size: %IR.IntegerType{value: 8},
                    type: :integer,
                    unit: 1
                  }}
               ]
             ]
    end

    # --- CONS OPERATOR ---

    test "non-nested cons operator with variable in head, in pattern" do
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

    test "non-nested cons operator with variable in head, in expression" do
      assert deconstruct(@ir_1, :expression) == [
               [:expression_value, {:list_index, 0}],
               [:expression_value, {:list_index, 0}, :list_tail],
               [:expression_value, {:list_index, 1}, :list_tail]
             ]
    end

    test "non-nested cons operator with variable in tail, in pattern" do
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

    test "non-nested cons operator with variable in tail, in expression" do
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

    # --- STRUCTS ---

    test "struct in pattern, with module specified" do
      # "%Module1{a: a, b: 2}" |> ir(%Context{pattern?: true})
      ir = %IR.MapType{
        data: [
          {%IR.AtomType{value: :__struct__}, %IR.AtomType{value: Module1}},
          {%IR.AtomType{value: :a}, %IR.Variable{name: :a}},
          {%IR.AtomType{value: :b}, %IR.IntegerType{value: 2}}
        ]
      }

      assert deconstruct(ir, :pattern) == [
               [
                 pattern_value: %IR.AtomType{value: Module1},
                 map_key: %IR.AtomType{value: :__struct__}
               ],
               [binding: :a, map_key: %IR.AtomType{value: :a}],
               [
                 pattern_value: %IR.IntegerType{value: 2},
                 map_key: %IR.AtomType{value: :b}
               ]
             ]
    end

    test "struct in pattern, with match placeholder instead of module" do
      # "%_{a: a, b: 2}" |> ir(%Context{pattern?: true})
      ir = %IR.MapType{
        data: [
          {%IR.AtomType{value: :__struct__}, %IR.MatchPlaceholder{}},
          {%IR.AtomType{value: :a}, %IR.Variable{name: :a}},
          {%IR.AtomType{value: :b}, %IR.IntegerType{value: 2}}
        ]
      }

      assert deconstruct(ir, :pattern) == [
               [:match_placeholder, {:map_key, %IR.AtomType{value: :__struct__}}],
               [binding: :a, map_key: %IR.AtomType{value: :a}],
               [pattern_value: %IR.IntegerType{value: 2}, map_key: %IR.AtomType{value: :b}]
             ]
    end

    test "struct in expression" do
      # "%Module1{a: a, b: 2}" |> ir(%Context{pattern?: false})
      ir = %IR.RemoteFunctionCall{
        module: %IR.AtomType{value: Module1},
        function: :__struct__,
        args: [
          %IR.ListType{
            data: [
              %IR.TupleType{data: [%IR.AtomType{value: :a}, %IR.Variable{name: :a}]},
              %IR.TupleType{data: [%IR.AtomType{value: :b}, %IR.IntegerType{value: 2}]}
            ]
          }
        ]
      }

      assert deconstruct(ir, :expression) == [[:expression_value]]
    end

    # --- OTHER ----

    # Only pin operators on pattern side need to be tested,
    # since pin operators on expression side shouldn't compile.
    test "pin operator" do
      # ^x
      ir = %IR.PinOperator{name: :my_var}

      assert deconstruct(ir, :pattern) == [[variable: :my_var]]
    end
  end
end
