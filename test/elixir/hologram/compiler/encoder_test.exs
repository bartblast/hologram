defmodule Hologram.Compiler.EncoderTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Encoder

  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR

  test "atom type" do
    ir = %IR.AtomType{value: :"aa\"bb\ncc"}

    assert encode(ir, %Context{}) == ~s/Type.atom("aa\\"bb\\ncc")/
  end

  describe "bitstring" do
    test "no segments" do
      ir = %IR.BitstringType{segments: []}

      assert encode(ir, %Context{}) == "Type.bitstring([])"
    end

    test "single segment" do
      ir = %IR.BitstringType{
        segments: [
          %IR.BitstringSegment{
            value: %IR.IntegerType{value: 1},
            modifiers: []
          }
        ]
      }

      assert encode(ir, %Context{}) ==
               "Type.bitstring([Type.bitstringSegment(Type.integer(1n), {})])"
    end

    test "multiple segments" do
      ir = %IR.BitstringType{
        segments: [
          %IR.BitstringSegment{
            value: %IR.IntegerType{value: 1},
            modifiers: []
          },
          %IR.BitstringSegment{
            value: %IR.IntegerType{value: 2},
            modifiers: []
          }
        ]
      }

      assert encode(ir, %Context{}) ==
               "Type.bitstring([Type.bitstringSegment(Type.integer(1n), {}), Type.bitstringSegment(Type.integer(2n), {})])"
    end
  end

  describe "bitstring segment" do
    test "no modifiers specified" do
      ir = %IR.BitstringSegment{
        value: %IR.IntegerType{value: 123},
        modifiers: []
      }

      assert encode(ir, %Context{}) == "Type.bitstringSegment(Type.integer(123n), {})"
    end

    test "all modifiers specified" do
      ir = %IR.BitstringSegment{
        value: %IR.IntegerType{value: 123},
        modifiers: [
          type: :integer,
          size: %IR.IntegerType{value: 16},
          unit: 1,
          signedness: :signed,
          endianness: :big
        ]
      }

      assert encode(ir, %Context{}) ==
               ~s/Type.bitstringSegment(Type.integer(123n), {type: "integer", size: Type.integer(16n), unit: 1n, signedness: "signed", endianness: "big"})/
    end

    test "single modifier specified" do
      ir = %IR.BitstringSegment{
        value: %IR.IntegerType{value: 123},
        modifiers: [endianness: :big]
      }

      assert encode(ir, %Context{}) ==
               ~s/Type.bitstringSegment(Type.integer(123n), {endianness: "big"})/
    end

    test "from string type" do
      ir = %IR.BitstringSegment{value: %IR.StringType{value: "abc"}, modifiers: [type: "utf16"]}

      assert encode(ir, %Context{}) ==
               ~s/Type.bitstringSegment(Type.string(\"abc\"), {type: "utf16"})/
    end

    test "from non-string type" do
      ir = %IR.BitstringSegment{
        value: %IR.IntegerType{value: 123},
        modifiers: [endianness: :big]
      }

      assert encode(ir, %Context{}) ==
               ~s/Type.bitstringSegment(Type.integer(123n), {endianness: "big"})/
    end
  end

  describe "cons operator" do
    @cons_operator_ir %IR.ConsOperator{
      head: %IR.IntegerType{value: 1},
      tail: %IR.ListType{data: [%IR.IntegerType{value: 2}, %IR.IntegerType{value: 3}]}
    }

    test "not inside pattern" do
      assert encode(@cons_operator_ir, %Context{pattern?: false}) ==
               "Interpreter.consOperator(Type.integer(1n), Type.list([Type.integer(2n), Type.integer(3n)])))"
    end

    test "inside pattern" do
      assert encode(@cons_operator_ir, %Context{pattern?: true}) ==
               "Type.consPattern(Type.integer(1n), Type.list([Type.integer(2n), Type.integer(3n)]))"
    end
  end

  test "float type" do
    assert encode(%IR.FloatType{value: 1.23}, %Context{}) == "Type.float(1.23)"
  end

  test "integer type" do
    assert encode(%IR.IntegerType{value: 123}, %Context{}) == "Type.integer(123n)"
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

      assert encode(ir, %Context{}) == ~s/Type.list([Type.integer(1n), Type.atom("abc")])/
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

      assert encode(ir, %Context{}) == ~s/Type.map([[Type.atom("a"), Type.integer(1n)]])/
    end

    test "multiple keys" do
      ir = %IR.MapType{
        data: [
          {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
          {%IR.AtomType{value: :b}, %IR.IntegerType{value: 2}}
        ]
      }

      assert encode(ir, %Context{}) ==
               ~s/Type.map([[Type.atom("a"), Type.integer(1n)], [Type.atom("b"), Type.integer(2n)]])/
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
               "Interpreter.matchOperator(Type.integer(1n), Type.integer(2n))"
    end

    test "variable in pattern" do
      # x = 2
      ir = %IR.MatchOperator{
        left: %IR.Variable{name: :x},
        right: %IR.IntegerType{value: 2}
      }

      assert encode(ir, %Context{}) ==
               ~s/Interpreter.matchOperator(Type.variablePattern("x"), Type.integer(2n))/
    end

    test "variable in expression" do
      # 1 = x
      ir = %IR.MatchOperator{
        left: %IR.IntegerType{value: 1},
        right: %IR.Variable{name: :x}
      }

      assert encode(ir, %Context{}) ==
               "Interpreter.matchOperator(Type.integer(1n), bindings.x)"
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
               ~s/Interpreter.matchOperator(Type.variablePattern("x"), Interpreter.matchOperator(Type.integer(2n), Type.integer(3n)))/
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
               ~s/Interpreter.matchOperator(Type.integer(1n), Interpreter.matchOperator(Type.variablePattern("x"), Type.integer(3n)))/
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
               "Interpreter.matchOperator(Type.integer(1n), Interpreter.matchOperator(Type.integer(2n), bindings.x))"
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
               ~s/Interpreter.matchOperator(Type.tuple([Interpreter.matchOperator(Type.variablePattern("a"), Type.variablePattern("b")), Type.integer(2n), Type.integer(3n)]), Interpreter.matchOperator(Type.tuple([Type.integer(1n), Interpreter.matchOperator(Type.variablePattern("c"), Type.variablePattern("d")), Type.integer(3n)]), Type.tuple([Type.integer(1n), Type.integer(2n), Interpreter.matchOperator(Type.variablePattern("e"), bindings.f)])))/
    end
  end

  test "string type" do
    ir = %IR.StringType{value: "aa\"bb\ncc"}

    assert encode(ir, %Context{}) == ~s/Type.bitstring("aa\\"bb\\ncc")/
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

      assert encode(ir, %Context{}) == ~s/Type.tuple([Type.integer(1n), Type.atom("abc")])/
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
