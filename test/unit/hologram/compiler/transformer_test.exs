defmodule Hologram.Compiler.TransformerTest do
  use Hologram.Test.UnitCase, async: true
  import Hologram.Compiler.Transformer
  alias Hologram.Compiler.IR

  # --- DATA TYPES --

  describe "anonymous function type" do
    test "arity" do
      # fn 1, 2 -> 9 end
      ast = {:fn, [line: 1], [{:->, [line: 1], [[1, 2], {:__block__, [], [9]}]}]}

      assert %IR.AnonymousFunctionType{arity: 2} = transform(ast)
    end

    test "params" do
      # fn a, b -> 9 end
      ast =
        {:fn, [line: 1],
         [
           {:->, [line: 1], [[{:a, [line: 1], nil}, {:b, [line: 1], nil}], {:__block__, [], [9]}]}
         ]}

      assert %IR.AnonymousFunctionType{
               params: [
                 %IR.Symbol{name: :a},
                 %IR.Symbol{name: :b}
               ]
             } = transform(ast)
    end

    test "bindings" do
      # fn 1, %{a: x, b: y} -> 9 end
      ast =
        {:fn, [line: 1],
         [
           {:->, [line: 1],
            [
              [1, {:%{}, [line: 1], [a: {:x, [line: 1], nil}, b: {:y, [line: 1], nil}]}],
              {:__block__, [], [9]}
            ]}
         ]}

      assert %IR.AnonymousFunctionType{
               bindings: [
                 %IR.Binding{
                   name: :x,
                   access_path: [
                     %IR.ParamAccess{index: 1},
                     %IR.MapAccess{key: %IR.AtomType{value: :a}}
                   ]
                 },
                 %IR.Binding{
                   name: :y,
                   access_path: [
                     %IR.ParamAccess{index: 1},
                     %IR.MapAccess{key: %IR.AtomType{value: :b}}
                   ]
                 }
               ]
             } = transform(ast)
    end

    test "body, single expression" do
      # fn -> 1 end
      ast = {:fn, [line: 1], [{:->, [line: 1], [[], {:__block__, [], [1]}]}]}

      assert %IR.AnonymousFunctionType{body: %IR.Block{expressions: [%IR.IntegerType{value: 1}]}} =
               transform(ast)
    end

    test "body, multiple expressions" do
      # fn ->
      #   1
      #   2
      # end
      ast = {:fn, [line: 1], [{:->, [line: 1], [[], {:__block__, [], [1, 2]}]}]}

      assert %IR.AnonymousFunctionType{
               body: %IR.Block{
                 expressions: [
                   %IR.IntegerType{value: 1},
                   %IR.IntegerType{value: 2}
                 ]
               }
             } = transform(ast)
    end

    # TODO: implement anonymous functions with multiple clauses
    test "multiple clauses" do
      # fn
      #  1 -> :a
      #  2 -> :b
      # end
      ast =
        {:fn, [line: 1],
         [
           {:->, [line: 2], [[1], {:__block__, [], [:a]}]},
           {:->, [line: 3], [[2], {:__block__, [], [:b]}]}
         ]}

      assert transform(ast) == %IR.NotSupportedExpression{
               type: :multi_clause_anonymous_function_type,
               ast: ast
             }
    end
  end

  test "atom type" do
    # :test
    ast = :test

    assert transform(ast) == %IR.AtomType{value: :test}
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

  test "struct type (explicit)" do
    # %A.B{x: 1, y: 2}
    ast = {:%, [line: 1], [{:__aliases__, [line: 1], [:A, :B]}, {:%{}, [line: 1], [x: 1, y: 2]}]}

    assert transform(ast) == %IR.StructType{
             module: %IR.Alias{segments: [:A, :B]},
             data: [
               {%IR.AtomType{value: :x}, %IR.IntegerType{value: 1}},
               {%IR.AtomType{value: :y}, %IR.IntegerType{value: 2}}
             ]
           }
  end

  test "struct type (implicit)" do
    ast =
      %Hologram.Test.Fixtures.Struct{a: 1, b: 2}
      |> Macro.escape()

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

  # --- OPERATORS ---

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

  test "match operator" do
    # %{a: x, b: y} = %{a: 1, b: 2}
    ast =
      {:=, [line: 1],
       [
         {:%{}, [line: 1], [a: {:x, [line: 1], nil}, b: {:y, [line: 1], nil}]},
         {:%{}, [line: 1], [a: 1, b: 2]}
       ]}

    assert transform(ast) == %IR.MatchOperator{
             bindings: [
               %IR.Binding{
                 name: :x,
                 access_path: [%IR.MatchAccess{}, %IR.MapAccess{key: %IR.AtomType{value: :a}}]
               },
               %IR.Binding{
                 name: :y,
                 access_path: [%IR.MatchAccess{}, %IR.MapAccess{key: %IR.AtomType{value: :b}}]
               }
             ],
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

  test "unary positive operator" do
    # +2
    ast = {:+, [line: 1], [2]}

    assert transform(ast) == %IR.UnaryPositiveOperator{
             value: %IR.IntegerType{value: 2}
           }
  end

  # --- OTHER IR ---

  test "alias" do
    # A.B
    ast = {:__aliases__, [line: 1], [:A, :B]}

    assert transform(ast) == %IR.Alias{segments: [:A, :B]}
  end

  test "block" do
    # do
    #   1
    #   2
    # end
    ast = {:__block__, [], [1, 2]}

    assert transform(ast) == %IR.Block{
             expressions: [
               %IR.IntegerType{value: 1},
               %IR.IntegerType{value: 2}
             ]
           }
  end

  test "symbol" do
    # a
    ast = {:a, [line: 1], nil}

    assert transform(ast) == %IR.Symbol{name: :a}
  end

  # --- HELPERS ---

  describe "transform_params/1" do
    test "function definition without params" do
      # def test do
      # end
      params = nil

      assert transform_params(params) == []
    end

    test "function definition with params" do
      # def test(a, b) do
      # end
      params = [{:a, [line: 1], nil}, {:b, [line: 1], nil}]

      assert transform_params(params) == [
               %IR.Symbol{name: :a},
               %IR.Symbol{name: :b}
             ]
    end

    test "function definition with explicit value pattern matching" do
      # def test(:a, 2) do
      # end
      params = [:a, 2]

      assert transform_params(params) == [
               %IR.AtomType{value: :a},
               %IR.IntegerType{value: 2}
             ]
    end
  end
end
