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

  test "string type" do
    # "test"
    ast = "test"

    assert transform(ast) == %IR.StringType{value: "test"}
  end
end
