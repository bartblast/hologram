defmodule Hologram.Compiler.TransformerTest do
  use Hologram.Test.UnitCase, async: true
  import Hologram.Compiler.Transformer
  alias Hologram.Compiler.IR

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

  test "module attribute" do
    # @a
    ast = {:@, [line: 1], [{:a, [line: 1], nil}]}

    assert transform(ast) == %IR.ModuleAttributeOperator{name: :a}
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

  describe "pipe operator" do
    test "non-nested pipeline" do
      # 100 |> div(2)
      ast = {:|>, [line: 1], [100, {:div, [line: 1], [2]}]}

      assert transform(ast) == %IR.FunctionCall{
               module: Kernel,
               function: :div,
               args: [
                 %IR.IntegerType{value: 100},
                 %IR.IntegerType{value: 2}
               ]
             }
    end

    test "nested pipeline" do
      # 100 |> div(2) |> div(3)
      ast =
        {:|>, [line: 1],
         [{:|>, [line: 1], [100, {:div, [line: 1], [2]}]}, {:div, [line: 1], [3]}]}

      assert transform(ast) == %IR.FunctionCall{
               module: Kernel,
               function: :div,
               args: [
                 %IR.FunctionCall{
                   module: Kernel,
                   function: :div,
                   args: [
                     %IR.IntegerType{value: 100},
                     %IR.IntegerType{value: 2}
                   ]
                 },
                 %IR.IntegerType{value: 3}
               ]
             }
    end
  end

  test "unary positive operator" do
    # +2
    ast = {:+, [line: 1], [2]}

    assert transform(ast) == %IR.UnaryPositiveOperator{
             value: %IR.IntegerType{value: 2}
           }
  end

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

  describe "anonymous function call" do
    test "without args" do
      # test.()
      ast = {{:., [line: 1], [{:test, [line: 1], nil}]}, [line: 1], []}

      assert transform(ast) == %IR.AnonymousFunctionCall{
               name: :test,
               args: []
             }
    end

    test "with single arg" do
      # test.(1)
      ast = {{:., [line: 1], [{:test, [line: 1], nil}]}, [line: 1], [1]}

      assert transform(ast) == %IR.AnonymousFunctionCall{
               name: :test,
               args: [%IR.IntegerType{value: 1}]
             }
    end

    test "with multiple args" do
      # test.(1, 2)
      ast = {{:., [line: 1], [{:test, [line: 1], nil}]}, [line: 1], [1, 2]}

      assert transform(ast) == %IR.AnonymousFunctionCall{
               name: :test,
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end
  end

  # --- PSEUDO-VARIABLES ---

  test "__ENV__ pseudo-variable" do
    # __ENV__
    ast = {:__ENV__, [line: 1], nil}

    assert transform(ast) == %IR.EnvPseudoVariable{}
  end

  test "__MODULE__ pseudo-variable" do
    # __MODULE__
    ast = {:__MODULE__, [line: 1], nil}

    assert transform(ast) == %IR.ModulePseudoVariable{}
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
