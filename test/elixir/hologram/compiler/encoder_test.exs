defmodule Hologram.Compiler.EncoderTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Encoder

  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR

  test "atom type" do
    ir = %IR.AtomType{value: :"aa\"bb\ncc"}

    assert encode(ir, %Context{}) == ~s/Type.atom("aa\\"bb\\ncc")/
  end

  test "float type" do
    assert encode(%IR.FloatType{value: 1.23}, %Context{}) == "Type.float(1.23)"
  end

  test "integer type" do
    assert encode(%IR.IntegerType{value: 123}, %Context{}) == "Type.integer(123)"
  end

  describe "list type" do
    test "empty" do
      assert encode(%IR.ListType{data: []}, %Context{}) == "Type.list([])"
    end

    test "non-empty" do
      ir = %IR.ListType{
        data: [
          %IR.IntegerType{value: 1},
          %IR.AtomType{value: :abc}
        ]
      }

      assert encode(ir, %Context{}) == ~s/Type.list([Type.integer(1), Type.atom("abc")])/
    end
  end

  describe "map type" do
    test "empty" do
      assert encode(%IR.MapType{data: []}, %Context{}) == "{type: 'map', data: {}}"
    end

    test "single key" do
      ir = %IR.MapType{
        data: [
          {
            %IR.AtomType{value: :a},
            %IR.IntegerType{value: 1}
          }
        ]
      }

      assert encode(ir, %Context{}) ==
               "{type: 'map', data: {'atom(a)': Type.integer(1)}}"
    end

    test "multiple keys" do
      ir = %IR.MapType{
        data: [
          {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
          {%IR.AtomType{value: :b}, %IR.IntegerType{value: 2}}
        ]
      }

      assert encode(ir, %Context{}) ==
               "{type: 'map', data: {'atom(a)': Type.integer(1), 'atom(b)': Type.integer(2)}}"
    end

    test "atom key" do
      ir = %IR.MapType{
        data: [
          {
            %IR.AtomType{value: :a},
            %IR.IntegerType{value: 1}
          }
        ]
      }

      assert encode(ir, %Context{}) ==
               "{type: 'map', data: {'atom(a)': Type.integer(1)}}"
    end

    test "float key" do
      ir = %IR.MapType{
        data: [
          {
            %IR.FloatType{value: 1.23},
            %IR.IntegerType{value: 1}
          }
        ]
      }

      assert encode(ir, %Context{}) ==
               "{type: 'map', data: {'float(1.23)': Type.integer(1)}}"
    end

    test "integer key" do
      ir = %IR.MapType{
        data: [
          {
            %IR.IntegerType{value: 987},
            %IR.IntegerType{value: 1}
          }
        ]
      }

      assert encode(ir, %Context{}) ==
               "{type: 'map', data: {'integer(987)': Type.integer(1)}}"
    end

    test "list key, empty list" do
      ir = %IR.MapType{
        data: [
          {
            %IR.ListType{data: []},
            %IR.IntegerType{value: 1}
          }
        ]
      }

      assert encode(ir, %Context{}) ==
               "{type: 'map', data: {'list()': Type.integer(1)}}"
    end

    test "list key, non-empty list" do
      ir = %IR.MapType{
        data: [
          {
            %IR.ListType{
              data: [
                %IR.IntegerType{value: 1},
                %IR.AtomType{value: :abc}
              ]
            },
            %IR.IntegerType{value: 1}
          }
        ]
      }

      assert encode(ir, %Context{}) ==
               "{type: 'map', data: {'list(integer(1),atom(abc))': Type.integer(1)}}"
    end

    test "map key, empty map" do
      ir = %IR.MapType{
        data: [
          {
            %IR.MapType{data: []},
            %IR.IntegerType{value: 1}
          }
        ]
      }

      assert encode(ir, %Context{}) ==
               "{type: 'map', data: {'map()': Type.integer(1)}}"
    end

    test "map key, non-empty map" do
      ir = %IR.MapType{
        data: [
          {
            %IR.MapType{
              data: [
                {%IR.IntegerType{value: 1}, %IR.FloatType{value: 1.23}},
                {%IR.AtomType{value: :b}, %IR.StringType{value: "abc"}}
              ]
            },
            %IR.IntegerType{value: 2}
          }
        ]
      }

      assert encode(ir, %Context{}) ==
               "{type: 'map', data: {'map(integer(1):float(1.23),atom(b):string(abc))': Type.integer(2)}}"
    end

    test "string key" do
      ir = %IR.MapType{
        data: [
          {
            %IR.StringType{value: "abc"},
            %IR.IntegerType{value: 1}
          }
        ]
      }

      assert encode(ir, %Context{}) ==
               "{type: 'map', data: {'string(abc)': Type.integer(1)}}"
    end

    test "tuple key, empty tuple" do
      ir = %IR.MapType{
        data: [
          {
            %IR.TupleType{data: []},
            %IR.IntegerType{value: 1}
          }
        ]
      }

      assert encode(ir, %Context{}) ==
               "{type: 'map', data: {'tuple()': Type.integer(1)}}"
    end

    test "tuple key, non-empty tuple" do
      ir = %IR.MapType{
        data: [
          {
            %IR.TupleType{
              data: [
                %IR.IntegerType{value: 1},
                %IR.AtomType{value: :abc}
              ]
            },
            %IR.IntegerType{value: 1}
          }
        ]
      }

      assert encode(ir, %Context{}) ==
               "{type: 'map', data: {'tuple(integer(1),atom(abc))': Type.integer(1)}}"
    end
  end

  describe "match operator" do
    test "literal value on both sides" do
      # 1 = 2
      ir = %IR.MatchOperator{
        left: %IR.IntegerType{value: 1},
        right: %IR.IntegerType{value: 2}
      }

      assert encode(ir, %Context{}) ==
               "Interpreter.matchOperator(Type.integer(1), Type.integer(2))"
    end

    test "variable in pattern" do
      # x = 2
      ir = %IR.MatchOperator{
        left: %IR.Variable{name: :x},
        right: %IR.IntegerType{value: 2}
      }

      assert encode(ir, %Context{}) ==
               ~s/Interpreter.matchOperator({type: 'variable', name: "x"}, Type.integer(2))/
    end

    test "variable in expression" do
      # 1 = x
      ir = %IR.MatchOperator{
        left: %IR.IntegerType{value: 1},
        right: %IR.Variable{name: :x}
      }

      assert encode(ir, %Context{}) ==
               "Interpreter.matchOperator(Type.integer(1), bindings.x)"
    end

    test "nested, variable in pattern" do
      # x = 2 = 3
      ir = %IR.MatchOperator{
        left: %IR.Variable{name: :x},
        right: %IR.MatchOperator{
          left: %IR.IntegerType{value: 2},
          right: %IR.IntegerType{value: 3}
        }
      }

      assert encode(ir, %Context{}) ==
               ~s/Interpreter.matchOperator({type: 'variable', name: "x"}, Interpreter.matchOperator(Type.integer(2), Type.integer(3)))/
    end

    test "nested, variable in the middle" do
      # 1 = x = 3
      ir = %IR.MatchOperator{
        left: %IR.IntegerType{value: 1},
        right: %IR.MatchOperator{
          left: %IR.Variable{name: :x},
          right: %IR.IntegerType{value: 3}
        }
      }

      assert encode(ir, %Context{}) ==
               ~s/Interpreter.matchOperator(Type.integer(1), Interpreter.matchOperator({type: 'variable', name: "x"}, Type.integer(3)))/
    end

    test "nested, variable in expression" do
      # 1 = 2 = x
      ir = %IR.MatchOperator{
        left: %IR.IntegerType{value: 1},
        right: %IR.MatchOperator{
          left: %IR.IntegerType{value: 2},
          right: %IR.Variable{name: :x}
        }
      }

      assert encode(ir, %Context{}) ==
               "Interpreter.matchOperator(Type.integer(1), Interpreter.matchOperator(Type.integer(2), bindings.x))"
    end

    test "nested multiple-times" do
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

      assert encode(ir, %Context{}) ==
               ~s/Interpreter.matchOperator({type: 'tuple', data: [Interpreter.matchOperator({type: 'variable', name: "a"}, {type: 'variable', name: "b"}), Type.integer(2), Type.integer(3)]}, Interpreter.matchOperator({type: 'tuple', data: [Type.integer(1), Interpreter.matchOperator({type: 'variable', name: "c"}, {type: 'variable', name: "d"}), Type.integer(3)]}, {type: 'tuple', data: [Type.integer(1), Type.integer(2), Interpreter.matchOperator({type: 'variable', name: "e"}, bindings.f)]}))/
    end
  end

  test "string type" do
    ir = %IR.StringType{value: "aa\"bb\ncc"}

    assert encode(ir, %Context{}) == ~s/Type.string("aa\\"bb\\ncc")/
  end

  describe "tuple type" do
    test "empty" do
      assert encode(%IR.TupleType{data: []}, %Context{}) == "{type: 'tuple', data: []}"
    end

    test "non-empty" do
      ir = %IR.TupleType{
        data: [
          %IR.IntegerType{value: 1},
          %IR.AtomType{value: :abc}
        ]
      }

      assert encode(ir, %Context{}) ==
               ~s/{type: 'tuple', data: [Type.integer(1), Type.atom("abc")]}/
    end
  end

  describe "variable" do
    test "not inside pattern" do
      assert encode(%IR.Variable{name: :my_var}, %Context{pattern?: false}) == "bindings.my_var"
    end

    test "inside pattern" do
      assert encode(%IR.Variable{name: :my_var}, %Context{pattern?: true}) ==
               ~s/{type: 'variable', name: "my_var"}/
    end
  end
end
