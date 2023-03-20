defmodule Hologram.Compiler.TransformerTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Transformer

  alias Hologram.Compiler.IR
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

  # --- DATA TYPES --

  test "atom type" do
    # :test
    ast = :test

    assert transform(ast) == %IR.AtomType{value: :test}
  end

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

  # --- CONTROL FLOW ---

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
