defmodule Hologram.Compiler.TransformerTest do
  alias Hologram.Test.Fixtures.Compiler.Transformer.Module2

  # --- OPERATORS ---

  describe "access operator" do
    test "data is a variable" do
      # a[:b]
      ast =
        {{:., [line: 1], [{:__aliases__, [alias: false], [:Access]}, :get]}, [line: 1],
         [{:a, [line: 1], nil}, :b]}

      assert transform(ast) == %IR.AccessOperator{
               data: %IR.Symbol{name: :a},
               key: %IR.AtomType{value: :b}
             }
    end

    test "data is an explicit value" do
      # %{a: 1, b: 2}[:b]
      ast =
        {{:., [line: 1], [{:__aliases__, [alias: false], [:Access]}, :get]}, [line: 1],
         [{:%{}, [line: 1], [a: 1, b: 2]}, :b]}

      assert transform(ast) == %IR.AccessOperator{
               data: %IR.MapType{
                 data: [
                   {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
                   {%IR.AtomType{value: :b}, %IR.IntegerType{value: 2}}
                 ]
               },
               key: %IR.AtomType{value: :b}
             }
    end
  end

  test "addition operator" do
    # a + 2
    ast = {:+, [line: 1], [{:a, [line: 1], nil}, 2]}

    assert transform(ast) == %IR.AdditionOperator{
             left: %IR.Symbol{name: :a},
             right: %IR.IntegerType{value: 2}
           }
  end

  test "cons operatoror" do
    # [h | t]
    ast = [{:|, [line: 1], [{:h, [line: 1], nil}, {:t, [line: 1], nil}]}]

    assert transform(ast) == %IR.ConsOperator{
             head: %IR.Symbol{name: :h},
             tail: %IR.Symbol{name: :t}
           }
  end

  test "division operator" do
    # a / 2
    ast = {:/, [line: 1], [{:a, [line: 1], nil}, 2]}

    assert transform(ast) == %IR.DivisionOperator{
             left: %IR.Symbol{name: :a},
             right: %IR.IntegerType{value: 2}
           }
  end

  describe "dot operator" do
    test "on symbol" do
      # a.x
      ast = {{:., [line: 1], [{:a, [line: 1], nil}, :x]}, [no_parens: true, line: 1], []}

      assert transform(ast) == %IR.DotOperator{
               left: %IR.Symbol{name: :a},
               right: %IR.AtomType{value: :x}
             }
    end

    test "on module attribute" do
      # @abc.x
      ast =
        {{:., [line: 1], [{:@, [line: 1], [{:abc, [line: 1], nil}]}, :x]},
         [no_parens: true, line: 1], []}

      assert transform(ast) == %IR.DotOperator{
               left: %IR.ModuleAttributeOperator{name: :abc},
               right: %IR.AtomType{value: :x}
             }
    end

    test "on expression" do
      # (3 + 4).x
      ast = {{:., [line: 1], [{:+, [line: 1], [3, 4]}, :x]}, [no_parens: true, line: 1], []}

      assert transform(ast) == %IR.DotOperator{
               left: %IR.AdditionOperator{
                 left: %IR.IntegerType{value: 3},
                 right: %IR.IntegerType{value: 4}
               },
               right: %IR.AtomType{value: :x}
             }
    end
  end

  test "equal to operator" do
    # 1 == 2
    ast = {:==, [line: 1], [1, 2]}

    assert transform(ast) == %IR.EqualToOperator{
             left: %IR.IntegerType{value: 1},
             right: %IR.IntegerType{value: 2}
           }
  end

  test "less than operator" do
    # 1 < 2
    ast = {:<, [line: 1], [1, 2]}

    assert transform(ast) == %IR.LessThanOperator{
             left: %IR.IntegerType{value: 1},
             right: %IR.IntegerType{value: 2}
           }
  end

  test "list concatenation operator" do
    # [1, 2] ++ [3, 4]
    ast = {:++, [line: 1], [[1, 2], [3, 4]]}

    assert transform(ast) == %IR.ListConcatenationOperator{
             left: %IR.ListType{
               data: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             },
             right: %IR.ListType{
               data: [
                 %IR.IntegerType{value: 3},
                 %IR.IntegerType{value: 4}
               ]
             }
           }
  end

  test "list subtraction operator" do
    # [1, 2] -- [3, 2]
    ast = {:--, [line: 1], [[1, 2], [3, 2]]}

    assert transform(ast) == %IR.ListSubtractionOperator{
             left: %IR.ListType{
               data: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             },
             right: %IR.ListType{
               data: [
                 %IR.IntegerType{value: 3},
                 %IR.IntegerType{value: 2}
               ]
             }
           }
  end

  test "match operator" do
    # %{a: x, b: y} = %{a: 1, b: 2}
    ast =
      {:=, [line: 1],
       [
         {:%{}, [line: 1], [a: {:x, [line: 1], nil}, b: {:y, [line: 1], nil}]},
         {:%{}, [line: 1], [a: 1, b: 2]}
       ]}

    assert transform(ast) == %IR.MatchOperator{
             left: %IR.MapType{
               data: [
                 {%IR.AtomType{value: :a}, %IR.Symbol{name: :x}},
                 {%IR.AtomType{value: :b}, %IR.Symbol{name: :y}}
               ]
             },
             right: %IR.MapType{
               data: [
                 {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
                 {%IR.AtomType{value: :b}, %IR.IntegerType{value: 2}}
               ]
             }
           }
  end

  test "membership operator" do
    # 1 in [2, 3]
    ast = {:in, [line: 1], [1, [2, 3]]}

    assert transform(ast) == %IR.MembershipOperator{
             left: %IR.IntegerType{value: 1},
             right: %IR.ListType{
               data: [
                 %IR.IntegerType{value: 2},
                 %IR.IntegerType{value: 3}
               ]
             }
           }
  end

  describe "module attribute operator" do
    test "AST obtained directly from source file" do
      # @my_attr
      ast = {:@, [line: 1], [{:my_attr, [line: 1], nil}]}

      assert transform(ast) == %IR.ModuleAttributeOperator{name: :my_attr}
    end

    test "AST returned from macro" do
      # apply(Module1, :"MACRO-macro_module_attribute_operator_1", [__ENV__])
      ast =
        {:@, [context: Module1, imports: [{1, Kernel}]],
         [{:my_attr, [context: Module1], Module1}]}

      assert transform(ast) == %IR.ModuleAttributeOperator{name: :my_attr}
    end
  end

  test "multiplication operator" do
    # a * 2
    ast = {:*, [line: 1], [{:a, [line: 1], nil}, 2]}

    assert transform(ast) == %IR.MultiplicationOperator{
             left: %IR.Symbol{name: :a},
             right: %IR.IntegerType{value: 2}
           }
  end

  test "not equal to operator" do
    # 1 != 2
    ast = {:!=, [line: 1], [1, 2]}

    assert transform(ast) == %IR.NotEqualToOperator{
             left: %IR.IntegerType{value: 1},
             right: %IR.IntegerType{value: 2}
           }
  end

  test "pin operator" do
    # ^my_var
    ast = {:^, [line: 1], [{:my_var, [line: 1], nil}]}

    assert transform(ast) == %IR.PinOperator{name: :my_var}
  end

  test "relaxed boolean and operator" do
    # 1 && 2
    ast = {:&&, [line: 1], [1, 2]}

    assert transform(ast) == %IR.RelaxedBooleanAndOperator{
             left: %IR.IntegerType{value: 1},
             right: %IR.IntegerType{value: 2}
           }
  end

  describe "relaxed boolean not operator" do
    test "block AST" do
      # !false
      ast = {:__block__, [], [{:!, [line: 1], [false]}]}

      assert transform(ast) == %IR.RelaxedBooleanNotOperator{
               value: %IR.BooleanType{value: false}
             }
    end

    test "non-block AST" do
      # true && !false
      ast = {:&&, [line: 1], [true, {:!, [line: 1], [false]}]}

      assert transform(ast) == %IR.RelaxedBooleanAndOperator{
               left: %IR.BooleanType{value: true},
               right: %IR.RelaxedBooleanNotOperator{value: %IR.BooleanType{value: false}}
             }
    end
  end

  test "relaxed boolean or operator" do
    # 1 || 2
    ast = {:||, [line: 1], [1, 2]}

    assert transform(ast) == %IR.RelaxedBooleanOrOperator{
             left: %IR.IntegerType{value: 1},
             right: %IR.IntegerType{value: 2}
           }
  end

  test "strict boolean and operator" do
    # true and false
    ast = {:and, [line: 1], [true, false]}

    assert transform(ast) == %IR.StrictBooleanAndOperator{
             left: %IR.BooleanType{value: true},
             right: %IR.BooleanType{value: false}
           }
  end

  test "subtraction operator" do
    # a - 2
    ast = {:-, [line: 1], [{:a, [line: 1], nil}, 2]}

    assert transform(ast) == %IR.SubtractionOperator{
             left: %IR.Symbol{name: :a},
             right: %IR.IntegerType{value: 2}
           }
  end

  test "type operator" do
    # str::binary
    ast = {:"::", [line: 1], [{:str, [line: 1], nil}, {:binary, [line: 1], nil}]}

    assert transform(ast) == %IR.TypeOperator{
             left: %IR.Symbol{name: :str},
             right: :binary
           }
  end

  # --- DATA TYPES --

  describe "binary type" do
    test "empty" do
      # <<>>
      ast = {:<<>>, [line: 1], []}

      assert transform(ast) == %IR.BinaryType{parts: []}
    end

    test "non-empty" do
      # <<1, 2>>
      ast = {:<<>>, [line: 1], [1, 2]}

      assert transform(ast) == %IR.BinaryType{
               parts: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end
  end

  test "boolean type" do
    # true
    ast = true

    assert transform(ast) == %IR.BooleanType{value: true}
  end

  test "float type" do
    # 1.0
    ast = 1.0

    assert transform(ast) == %IR.FloatType{value: 1.0}
  end

  test "integer type" do
    # 1
    ast = 1

    assert transform(ast) == %IR.IntegerType{value: 1}
  end

  test "list type" do
    # [1, 2]
    ast = [1, 2]

    assert transform(ast) == %IR.ListType{
             data: [
               %IR.IntegerType{value: 1},
               %IR.IntegerType{value: 2}
             ]
           }
  end

  test "map type " do
    # %{a: 1, b: 2}
    ast = {:%{}, [line: 1], [a: 1, b: 2]}

    assert transform(ast) == %IR.MapType{
             data: [
               {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
               {%IR.AtomType{value: :b}, %IR.IntegerType{value: 2}}
             ]
           }
  end

  test "nil type" do
    # nil
    ast = nil

    assert transform(ast) == %IR.NilType{}
  end

  test "string type" do
    # "test"
    ast = "test"

    assert transform(ast) == %IR.StringType{value: "test"}
  end

  describe "struct type" do
    test "explicit syntax" do
      # %A.B{x: 1, y: 2}
      ast =
        {:%, [line: 1], [{:__aliases__, [line: 1], [:A, :B]}, {:%{}, [line: 1], [x: 1, y: 2]}]}

      assert transform(ast) == %IR.StructType{
               module: %IR.Alias{segments: [:A, :B]},
               data: [
                 {%IR.AtomType{value: :x}, %IR.IntegerType{value: 1}},
                 {%IR.AtomType{value: :y}, %IR.IntegerType{value: 2}}
               ]
             }
    end

    test "implicit syntax" do
      # %Hologram.Test.Fixtures.Struct{a: 1, b: 2} |> Macro.escape()
      ast = {:%{}, [], [__struct__: Hologram.Test.Fixtures.Struct, a: 1, b: 2]}

      assert transform(ast) == %IR.StructType{
               module: %IR.ModuleType{
                 module: Hologram.Test.Fixtures.Struct,
                 segments: [:Hologram, :Test, :Fixtures, :Struct]
               },
               data: [
                 {%IR.AtomType{value: :a}, %IR.IntegerType{value: 1}},
                 {%IR.AtomType{value: :b}, %IR.IntegerType{value: 2}}
               ]
             }
    end
  end

  describe "tuple type" do
    test "2-element tuple" do
      # {1, 2}
      ast = {1, 2}

      assert transform(ast) == %IR.TupleType{
               data: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end

    test "non-2-element tuple" do
      # {1, 2, 3}
      ast = {:{}, [line: 1], [1, 2, 3]}

      assert transform(ast) == %IR.TupleType{
               data: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2},
                 %IR.IntegerType{value: 3}
               ]
             }
    end
  end

  # --- IDENTIFIERS ---

  describe "alias" do
    test "non-contextual" do
      # Aaa.Bbb
      ast = {:__aliases__, [line: 1], [:Aaa, :Bbb]}

      assert transform(ast) == %IR.Alias{segments: [:Aaa, :Bbb]}
    end

    test "contextual, e.g. aliased inside a macro" do
      # {{:., [], [ast, :macro_2a]}, [], []} = apply(Module1, :"MACRO-macro_call_3", [__ENV__])
      ast = {:__aliases__, [alias: Module2], [:InnerAlias]}

      assert transform(ast) == %IR.ModuleType{
               module: Module2,
               segments: [:Hologram, :Test, :Fixtures, :Compiler, :Transformer, :Module2]
             }
    end
  end

  test "symbol" do
    # a
    ast = {:a, [line: 1], nil}

    assert transform(ast) == %IR.Symbol{name: :a}
  end
end
