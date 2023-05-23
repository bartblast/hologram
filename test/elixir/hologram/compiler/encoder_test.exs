defmodule Hologram.Compiler.EncoderTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Encoder

  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR

  test "atom type" do
    ir = %IR.AtomType{value: :"aa\"bb\ncc"}

    assert encode(ir, %Context{}) == ~s/Type.atom("aa\\"bb\\ncc")/
  end

  describe "bitstring segment" do
    test "all fields applicable" do
      ir = %IR.BitstringSegment{
        value: %IR.IntegerType{value: 123},
        type: :integer,
        size: %IR.IntegerType{value: 16},
        unit: 1,
        signedness: :signed,
        endianness: :big
      }

      assert encode(ir, %Context{}) ==
               ~s/[Type.integer(123), "integer", Type.integer(16), 1, "signed", "big"]/
    end

    test "signedness not applicable" do
      ir = %IR.BitstringSegment{
        value: %IR.IntegerType{value: 123},
        type: :integer,
        size: %IR.IntegerType{value: 16},
        unit: 1,
        signedness: :not_applicable,
        endianness: :big
      }

      assert encode(ir, %Context{}) ==
               ~s/[Type.integer(123), "integer", Type.integer(16), 1, null, "big"]/
    end

    test "endianness not applicable" do
      ir = %IR.BitstringSegment{
        value: %IR.IntegerType{value: 123},
        type: :integer,
        size: %IR.IntegerType{value: 16},
        unit: 1,
        signedness: :signed,
        endianness: :not_applicable
      }

      assert encode(ir, %Context{}) ==
               ~s/[Type.integer(123), "integer", Type.integer(16), 1, "signed", null]/
    end
  end

  describe "cons operator" do
    @cons_operator_ir %IR.ConsOperator{
      head: %IR.IntegerType{value: 1},
      tail: %IR.ListType{data: [%IR.IntegerType{value: 2}, %IR.IntegerType{value: 3}]}
    }

    test "not inside pattern" do
      assert encode(@cons_operator_ir, %Context{pattern?: false}) ==
               "Interpreter.consOperator(Type.integer(1), Type.list([Type.integer(2), Type.integer(3)])))"
    end

    test "inside pattern" do
      assert encode(@cons_operator_ir, %Context{pattern?: true}) ==
               "Type.consPattern(Type.integer(1), Type.list([Type.integer(2), Type.integer(3)]))"
    end
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
      assert encode(%IR.MapType{data: []}, %Context{}) == "Type.map([])"
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

      assert encode(ir, %Context{}) == ~s/Type.map([[Type.atom("a"), Type.integer(1)]])/
    end

    test "multiple keys" do
      ir = %IR.MapType{
        data: [
          {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
          {%IR.AtomType{value: :b}, %IR.IntegerType{value: 2}}
        ]
      }

      assert encode(ir, %Context{}) ==
               ~s/Type.map([[Type.atom("a"), Type.integer(1)], [Type.atom("b"), Type.integer(2)]])/
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
               ~s/Interpreter.matchOperator(Type.variablePattern("x"), Type.integer(2))/
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
               ~s/Interpreter.matchOperator(Type.variablePattern("x"), Interpreter.matchOperator(Type.integer(2), Type.integer(3)))/
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
               ~s/Interpreter.matchOperator(Type.integer(1), Interpreter.matchOperator(Type.variablePattern("x"), Type.integer(3)))/
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
               ~s/Interpreter.matchOperator(Type.tuple([Interpreter.matchOperator(Type.variablePattern("a"), Type.variablePattern("b")), Type.integer(2), Type.integer(3)]), Interpreter.matchOperator(Type.tuple([Type.integer(1), Interpreter.matchOperator(Type.variablePattern("c"), Type.variablePattern("d")), Type.integer(3)]), Type.tuple([Type.integer(1), Type.integer(2), Interpreter.matchOperator(Type.variablePattern("e"), bindings.f)])))/
    end
  end

  test "string type" do
    ir = %IR.StringType{value: "aa\"bb\ncc"}

    assert encode(ir, %Context{}) == ~s/Type.string("aa\\"bb\\ncc")/
  end

  describe "tuple type" do
    test "empty" do
      assert encode(%IR.TupleType{data: []}, %Context{}) == "Type.tuple([])"
    end

    test "non-empty" do
      ir = %IR.TupleType{
        data: [
          %IR.IntegerType{value: 1},
          %IR.AtomType{value: :abc}
        ]
      }

      assert encode(ir, %Context{}) == ~s/Type.tuple([Type.integer(1), Type.atom("abc")])/
    end
  end

  describe "variable" do
    test "not inside pattern" do
      assert encode(%IR.Variable{name: :my_var}, %Context{pattern?: false}) == "bindings.my_var"
    end

    test "inside pattern" do
      assert encode(%IR.Variable{name: :my_var}, %Context{pattern?: true}) ==
               ~s/Type.variablePattern("my_var")/
    end
  end

  describe "escape_js_identifier/1" do
    test "escape characters which are not allowed in JS identifiers" do
      assert escape_js_identifier("@[^`{") == "$64$91$94$96$123"
    end

    test "escape $ (dollar sign) character" do
      assert escape_js_identifier("$") == "$36"
    end

    test "does not escape characters which are allowed in JS identifiers" do
      str = "059AKZakz_"
      assert escape_js_identifier(str) == str
    end
  end
end
