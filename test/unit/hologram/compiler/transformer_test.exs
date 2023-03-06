defmodule Hologram.Compiler.TransformerTest do
  use Hologram.Test.UnitCase, async: true
  import Hologram.Compiler.Transformer

  alias Hologram.Compiler.IR
  alias Hologram.Test.Fixtures.Compiler.Transformer.Module1
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

  test "module attribute operator" do
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

      assert transform(ast) == %IR.Call{
               module: nil,
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

      assert transform(ast) == %IR.Call{
               module: nil,
               function: :div,
               args: [
                 %IR.Call{
                   module: nil,
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

  test "unary negative operator" do
    # -2
    ast = {:-, [line: 1], [2]}

    assert transform(ast) == %IR.UnaryNegativeOperator{
             value: %IR.IntegerType{value: 2}
           }
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
  end

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

  # --- DEFINITIONS ---

  describe "function definition" do
    test "name" do
      # def my_fun(a, b) do
      # end
      ast =
        {:def, [line: 1],
         [
           {:my_fun, [line: 1], [{:a, [line: 1], nil}, {:b, [line: 1], nil}]},
           [do: {:__block__, [], []}]
         ]}

      assert %IR.FunctionDefinition{name: :my_fun} = transform(ast)
    end

    test "without params" do
      # def my_fun do
      # end
      ast = {:def, [line: 1], [{:my_fun, [line: 1], nil}, [do: {:__block__, [], []}]]}

      assert %IR.FunctionDefinition{arity: 0, params: []} = transform(ast)
    end

    test "with params" do
      # def my_fun(a, b) do
      # end
      ast =
        {:def, [line: 1],
         [
           {:my_fun, [line: 1], [{:a, [line: 1], nil}, {:b, [line: 1], nil}]},
           [do: {:__block__, [], []}]
         ]}

      assert %IR.FunctionDefinition{
               arity: 2,
               params: [
                 %IR.Symbol{name: :a},
                 %IR.Symbol{name: :b}
               ]
             } = transform(ast)
    end

    test "bindings" do
      # def my_fun(1, %{a: x, b: y}) do
      # end
      ast =
        {:def, [line: 1],
         [
           {:my_fun, [line: 1],
            [1, {:%{}, [line: 1], [a: {:x, [line: 1], nil}, b: {:y, [line: 1], nil}]}]},
           [do: {:__block__, [], []}]
         ]}

      assert %IR.FunctionDefinition{
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

    test "empty body" do
      # def my_fun do
      # end
      ast = {:def, [line: 1], [{:my_fun, [line: 1], nil}, [do: {:__block__, [], []}]]}

      assert %IR.FunctionDefinition{body: %IR.Block{expressions: []}} = transform(ast)
    end

    test "body with single expression" do
      # def my_fun do
      #   1
      # end
      ast = {:def, [line: 1], [{:my_fun, [line: 1], nil}, [do: {:__block__, [], [1]}]]}

      assert %IR.FunctionDefinition{
               body: %IR.Block{
                 expressions: [
                   %IR.IntegerType{value: 1}
                 ]
               }
             } = transform(ast)
    end

    test "body with multiple expressions" do
      # def my_fun do
      #   1
      #   2
      # end
      ast = {:def, [line: 1], [{:my_fun, [line: 1], nil}, [do: {:__block__, [], [1, 2]}]]}

      assert %IR.FunctionDefinition{
               body: %IR.Block{
                 expressions: [
                   %IR.IntegerType{value: 1},
                   %IR.IntegerType{value: 2}
                 ]
               }
             } = transform(ast)
    end

    test "public visibility" do
      # def my_fun do
      # end
      ast = {:def, [line: 1], [{:my_fun, [line: 1], nil}, [do: {:__block__, [], []}]]}

      assert %IR.FunctionDefinition{visibility: :public} = transform(ast)
    end

    test "private visibility" do
      # defp my_fun do
      # end
      ast = {:defp, [line: 1], [{:my_fun, [line: 1], nil}, [do: {:__block__, [], []}]]}

      assert %IR.FunctionDefinition{visibility: :private} = transform(ast)
    end
  end

  test "module attribute definition" do
    # @abc 1 + 2
    ast = {:@, [line: 1], [{:abc, [line: 1], [{:+, [line: 1], [1, 2]}]}]}

    assert transform(ast) == %IR.ModuleAttributeDefinition{
             name: :abc,
             expression: %IR.AdditionOperator{
               left: %IR.IntegerType{value: 1},
               right: %IR.IntegerType{value: 2}
             }
           }
  end

  describe "module definition" do
    test "empty body" do
      # defmodule A.B do end
      ast =
        {:defmodule, [line: 1], [{:__aliases__, [line: 1], [:A, :B]}, [do: {:__block__, [], []}]]}

      assert transform(ast) == %IR.ModuleDefinition{
               module: %IR.Alias{segments: [:A, :B]},
               body: %IR.Block{expressions: []}
             }
    end

    test "single expression body" do
      # defmodule A.B do
      #   1
      # end
      ast =
        {:defmodule, [line: 1],
         [{:__aliases__, [line: 1], [:A, :B]}, [do: {:__block__, [], [1]}]]}

      assert transform(ast) == %IR.ModuleDefinition{
               module: %IR.Alias{segments: [:A, :B]},
               body: %IR.Block{
                 expressions: [
                   %IR.IntegerType{value: 1}
                 ]
               }
             }
    end

    test "multiple expressions body" do
      # defmodule A.B do
      #   1
      #   2
      # end
      ast =
        {:defmodule, [line: 1],
         [{:__aliases__, [line: 1], [:A, :B]}, [do: {:__block__, [], [1, 2]}]]}

      assert transform(ast) == %IR.ModuleDefinition{
               module: %IR.Alias{segments: [:A, :B]},
               body: %IR.Block{
                 expressions: [
                   %IR.IntegerType{value: 1},
                   %IR.IntegerType{value: 2}
                 ]
               }
             }
    end
  end

  # --- DIRECTIVES ---

  describe "alias directive" do
    test "default 'as' option" do
      # alias A.B
      ast = {:alias, [line: 1], [{:__aliases__, [line: 1], [:A, :B]}]}

      assert transform(ast) == %IR.AliasDirective{alias_segs: [:A, :B], as: :B}
    end

    test "custom 'as' option" do
      # alias A.B, as: C
      ast =
        {:alias, [line: 1],
         [{:__aliases__, [line: 1], [:A, :B]}, [as: {:__aliases__, [line: 1], [:C]}]]}

      assert transform(ast) == %IR.AliasDirective{alias_segs: [:A, :B], as: :C}
    end

    test "'warn' option" do
      # alias A.B, warn: false
      ast = {:alias, [line: 1], [{:__aliases__, [line: 1], [:A, :B]}, [warn: false]]}

      assert transform(ast) == %IR.AliasDirective{alias_segs: [:A, :B], as: :B}
    end

    test "'as' option + 'warn' option" do
      # alias A.B, as: C, warn: false
      ast =
        {:alias, [line: 1],
         [
           {:__aliases__, [line: 1], [:A, :B]},
           [as: {:__aliases__, [line: 1], [:C]}, warn: false]
         ]}

      assert transform(ast) == %IR.AliasDirective{alias_segs: [:A, :B], as: :C}
    end

    test "multi-alias without options" do
      # alias A.B.{C, D}
      ast =
        {:alias, [line: 1],
         [
           {{:., [line: 1], [{:__aliases__, [line: 1], [:A, :B]}, :{}]}, [line: 1],
            [{:__aliases__, [line: 1], [:C]}, {:__aliases__, [line: 1], [:D]}]}
         ]}

      assert transform(ast) == [
               %IR.AliasDirective{alias_segs: [:A, :B, :C], as: :C},
               %IR.AliasDirective{alias_segs: [:A, :B, :D], as: :D}
             ]
    end

    test "multi-alias with options" do
      # alias A.B.{C, D}, warn: false
      ast =
        {:alias, [line: 1],
         [
           {{:., [line: 1], [{:__aliases__, [line: 1], [:A, :B]}, :{}]}, [line: 1],
            [{:__aliases__, [line: 1], [:C]}, {:__aliases__, [line: 1], [:D]}]},
           [warn: false]
         ]}

      assert transform(ast) == [
               %IR.AliasDirective{alias_segs: [:A, :B, :C], as: :C},
               %IR.AliasDirective{alias_segs: [:A, :B, :D], as: :D}
             ]
    end
  end

  describe "import directive" do
    test "without options" do
      # import A.B
      ast = {:import, [line: 1], [{:__aliases__, [line: 1], [:A, :B]}]}

      assert transform(ast) == %IR.ImportDirective{alias_segs: [:A, :B], only: [], except: []}
    end

    test "with 'only' option" do
      # import A.B, only: [xyz: 2]
      ast = {:import, [line: 1], [{:__aliases__, [line: 1], [:A, :B]}, [only: [xyz: 2]]]}

      assert transform(ast) == %IR.ImportDirective{
               alias_segs: [:A, :B],
               only: [xyz: 2],
               except: []
             }
    end

    test "with 'except' option" do
      # import A.B, except: [xyz: 2]
      ast = {:import, [line: 1], [{:__aliases__, [line: 1], [:A, :B]}, [except: [xyz: 2]]]}

      assert transform(ast) == %IR.ImportDirective{
               alias_segs: [:A, :B],
               only: [],
               except: [xyz: 2]
             }
    end

    test "with both 'only' and 'except' options" do
      # import A.B, only: [abc: 1], except: [xyz: 2]
      ast =
        {:import, [line: 1],
         [{:__aliases__, [line: 1], [:A, :B]}, [only: [abc: 1], except: [xyz: 2]]]}

      assert transform(ast) == %IR.ImportDirective{
               alias_segs: [:A, :B],
               only: [abc: 1],
               except: [xyz: 2]
             }
    end
  end

  test "require directive" do
    # require A.B
    ast = {:require, [line: 1], [{:__aliases__, [line: 1], [:A, :B]}]}

    assert transform(ast) == %IR.IgnoredExpression{type: :require_directive}
  end

  describe "use directive" do
    test "without opts" do
      # use A.B
      ast = {:use, [line: 1], [{:__aliases__, [line: 1], [:A, :B]}]}

      assert transform(ast) == %IR.UseDirective{alias_segs: [:A, :B], opts: []}
    end

    test "with opts" do
      # use A.B, a: 1, b: 2
      ast = {:use, [line: 1], [{:__aliases__, [line: 1], [:A, :B]}, [a: 1, b: 2]]}

      assert transform(ast) == %IR.UseDirective{
               alias_segs: [:A, :B],
               opts: %IR.ListType{
                 data: [
                   %IR.TupleType{
                     data: [
                       %IR.AtomType{value: :a},
                       %IR.IntegerType{value: 1}
                     ]
                   },
                   %IR.TupleType{
                     data: [
                       %IR.AtomType{value: :b},
                       %IR.IntegerType{value: 2}
                     ]
                   }
                 ]
               }
             }
    end
  end

  # --- CONTROL FLOW ---

  test "alias" do
    # A.B
    ast = {:__aliases__, [line: 1], [:A, :B]}

    assert transform(ast) == %IR.Alias{segments: [:A, :B]}
  end

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

  describe "call" do
    test "without args" do
      # my_fun()
      ast = {:my_fun, [line: 1], []}

      assert transform(ast) == %IR.Call{
               module: nil,
               function: :my_fun,
               args: []
             }
    end

    test "with args" do
      # my_fun(1, 2)
      ast = {:my_fun, [line: 1], [1, 2]}

      assert transform(ast) == %IR.Call{
               module: nil,
               function: :my_fun,
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end

    test "on symbol, without args" do
      # a.x()
      ast = {{:., [line: 1], [{:a, [line: 1], nil}, :x]}, [line: 1], []}

      assert transform(ast) == %IR.Call{
               module: %IR.Symbol{name: :a},
               function: :x,
               args: []
             }
    end

    test "on symbol, with args" do
      # a.x(1, 2)
      ast = {{:., [line: 1], [{:a, [line: 1], nil}, :x]}, [line: 1], [1, 2]}

      assert transform(ast) == %IR.Call{
               module: %IR.Symbol{name: :a},
               function: :x,
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end

    test "on alias, without args, without parenthesis" do
      # Abc.my_fun
      ast =
        {{:., [line: 1], [{:__aliases__, [line: 1], [:Abc]}, :my_fun]},
         [no_parens: true, line: 1], []}

      assert transform(ast) == %IR.Call{
               module: %IR.Alias{segments: [:Abc]},
               function: :my_fun,
               args: []
             }
    end

    test "on alias, without args, with parenthesis" do
      # Abc.my_fun()
      ast = {{:., [line: 1], [{:__aliases__, [line: 1], [:Abc]}, :my_fun]}, [line: 1], []}

      assert transform(ast) == %IR.Call{
               module: %IR.Alias{segments: [:Abc]},
               function: :my_fun,
               args: []
             }
    end

    test "on alias, with args" do
      # Abc.my_fun(1, 2)
      ast = {{:., [line: 1], [{:__aliases__, [line: 1], [:Abc]}, :my_fun]}, [line: 1], [1, 2]}

      assert transform(ast) == %IR.Call{
               module: %IR.Alias{segments: [:Abc]},
               function: :my_fun,
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end

    test "on module attribute, without args" do
      # @my_attr.my_fun()
      ast =
        {{:., [line: 1], [{:@, [line: 1], [{:my_attr, [line: 1], nil}]}, :my_fun]}, [line: 1], []}

      assert transform(ast) == %IR.Call{
               module: %IR.ModuleAttributeOperator{name: :my_attr},
               function: :my_fun,
               args: []
             }
    end

    test "on module attribute, with args" do
      # @my_attr.my_fun(1, 2)
      ast =
        {{:., [line: 1], [{:@, [line: 1], [{:my_attr, [line: 1], nil}]}, :my_fun]}, [line: 1],
         [1, 2]}

      assert transform(ast) == %IR.Call{
               module: %IR.ModuleAttributeOperator{name: :my_attr},
               function: :my_fun,
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end

    test "on expression, without args" do
      # (3 + 4).my_fun()
      ast = {{:., [line: 1], [{:+, [line: 1], [3, 4]}, :my_fun]}, [line: 1], []}

      assert transform(ast) == %IR.Call{
               module: %IR.AdditionOperator{
                 left: %IR.IntegerType{value: 3},
                 right: %IR.IntegerType{value: 4}
               },
               function: :my_fun,
               args: []
             }
    end

    test "on expression, with args" do
      # (3 + 4).my_fun(1, 2)
      ast = {{:., [line: 1], [{:+, [line: 1], [3, 4]}, :my_fun]}, [line: 1], [1, 2]}

      assert transform(ast) == %IR.Call{
               module: %IR.AdditionOperator{
                 left: %IR.IntegerType{value: 3},
                 right: %IR.IntegerType{value: 4}
               },
               function: :my_fun,
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end

    test "on __MODULE__ pseudo-variable, without args, without parenthesis" do
      # __MODULE__.my_fun
      ast =
        {{:., [line: 1], [{:__MODULE__, [line: 1], nil}, :my_fun]}, [no_parens: true, line: 1],
         []}

      assert transform(ast) == %IR.Call{
               module: %IR.ModulePseudoVariable{},
               function: :my_fun,
               args: []
             }
    end

    test "on __MODULE__ pseudo-variable, without args, with parenthesis" do
      # __MODULE__.my_fun()
      ast = {{:., [line: 1], [{:__MODULE__, [line: 1], nil}, :my_fun]}, [line: 1], []}

      assert transform(ast) == %IR.Call{
               module: %IR.ModulePseudoVariable{},
               function: :my_fun,
               args: []
             }
    end

    test "on __MODULE__ pseudo-variable, with args" do
      # __MODULE__.my_fun(1, 2)
      ast = {{:., [line: 1], [{:__MODULE__, [line: 1], nil}, :my_fun]}, [line: 1], [1, 2]}

      assert transform(ast) == %IR.Call{
               module: %IR.ModulePseudoVariable{},
               function: :my_fun,
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             }
    end

    test "Erlang function, without args, without parenthesis" do
      # :my_module.my_fun
      ast = {{:., [line: 1], [:my_module, :my_fun]}, [no_parens: true, line: 1], []}

      assert transform(ast) == %IR.FunctionCall{
               module: :my_module,
               function: :my_fun,
               args: [],
               erlang: true
             }
    end

    test "Erlang function, without args, with parenthesis" do
      # :my_module.my_fun()
      ast = {{:., [line: 1], [:my_module, :my_fun]}, [line: 1], []}

      assert transform(ast) == %IR.FunctionCall{
               module: :my_module,
               function: :my_fun,
               args: [],
               erlang: true
             }
    end

    test "Erlang function, with args" do
      # :my_module.my_fun(1, 2)
      ast = {{:., [line: 1], [:my_module, :my_fun]}, [line: 1], [1, 2]}

      assert transform(ast) == %IR.FunctionCall{
               module: :my_module,
               function: :my_fun,
               args: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ],
               erlang: true
             }
    end

    test "string interpolation" do
      # "#{test}"
      ast =
        {:<<>>, [line: 1],
         [
           {:"::", [line: 1],
            [
              {{:., [line: 1], [{:__aliases__, [alias: false], [:Kernel]}, :to_string]},
               [line: 1], [{:test, [line: 1], nil}]},
              {:binary, [line: 1], nil}
            ]}
         ]}

      assert transform(ast) == %IR.BinaryType{
               parts: [
                 %IR.TypeOperator{
                   left: %IR.Call{
                     module: %IR.Alias{segments: [:Kernel]},
                     function: :to_string,
                     args: [%IR.Symbol{name: :test}]
                   },
                   right: :binary
                 }
               ]
             }
    end

    test "imported macro nested in another macro, called without args, with parenthesis" do
      # apply(Module1, :"MACRO-macro_1a", [__ENV__])
      ast = {:macro_2a, [context: Module1, imports: [{0, Module2}]], []}

      assert transform(ast) == %IR.Call{
               module: %IR.ModuleType{
                 module: Module2,
                 segments: [:Hologram, :Test, :Fixtures, :Compiler, :Transformer, :Module2]
               },
               function: :macro_2a,
               args: []
             }
    end

    test "imported macro nested in another macro, called without args, without parenthesis" do
      # apply(Module1, :"MACRO-macro_1b", [__ENV__])
      ast = {:macro_2a, [context: Module1, imports: [{0, Module2}]], Module1}

      assert transform(ast) == %IR.Call{
               module: %IR.ModuleType{
                 module: Module2,
                 segments: [:Hologram, :Test, :Fixtures, :Compiler, :Transformer, :Module2]
               },
               function: :macro_2a,
               args: []
             }
    end
  end

  describe "case expression" do
    test "single clause with single expression body" do
      # case x do
      #   1 -> :ok
      # end
      ast =
        {:case, [line: 1],
         [
           {:x, [line: 1], nil},
           [do: [{:->, [line: 2], [[1], {:__block__, [], [:ok]}]}]]
         ]}

      assert transform(ast) == %IR.CaseExpression{
               clauses: [
                 %{
                   bindings: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.AtomType{value: :ok}
                     ]
                   },
                   pattern: %IR.IntegerType{value: 1}
                 }
               ],
               condition: %IR.Symbol{name: :x}
             }
    end

    test "single clause with multiple expression body" do
      # case x do
      #   1 ->
      #     :expr_1
      #     :expr_2
      # end
      ast =
        {:case, [line: 1],
         [
           {:x, [line: 1], nil},
           [do: [{:->, [line: 2], [[1], {:__block__, [], [:expr_1, :expr_2]}]}]]
         ]}

      assert transform(ast) == %IR.CaseExpression{
               clauses: [
                 %{
                   bindings: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.AtomType{value: :expr_1},
                       %IR.AtomType{value: :expr_2}
                     ]
                   },
                   pattern: %IR.IntegerType{value: 1}
                 }
               ],
               condition: %IR.Symbol{name: :x}
             }
    end

    test "multiple clauses with single expression bodies" do
      # case x do
      #   1 -> :ok
      #   2 -> :error
      # end
      ast =
        {:case, [line: 1],
         [
           {:x, [line: 1], nil},
           [
             do: [
               {:->, [line: 2], [[1], {:__block__, [], [:ok]}]},
               {:->, [line: 3], [[2], {:__block__, [], [:error]}]}
             ]
           ]
         ]}

      assert transform(ast) == %IR.CaseExpression{
               condition: %IR.Symbol{name: :x},
               clauses: [
                 %{
                   bindings: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.AtomType{value: :ok}
                     ]
                   },
                   pattern: %IR.IntegerType{value: 1}
                 },
                 %{
                   bindings: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.AtomType{value: :error}
                     ]
                   },
                   pattern: %IR.IntegerType{value: 2}
                 }
               ]
             }
    end

    test "multiple clauses with multiple expression bodies" do
      # case x do
      #   1 ->
      #     :expr_1
      #     :expr_2
      #   2 ->
      #     :expr_3
      #     :expr_4
      # end
      ast =
        {:case, [line: 1],
         [
           {:x, [line: 1], nil},
           [
             do: [
               {:->, [line: 2], [[1], {:__block__, [], [:expr_1, :expr_2]}]},
               {:->, [line: 5], [[2], {:__block__, [], [:expr_3, :expr_4]}]}
             ]
           ]
         ]}

      assert transform(ast) == %IR.CaseExpression{
               condition: %IR.Symbol{name: :x},
               clauses: [
                 %{
                   bindings: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.AtomType{value: :expr_1},
                       %IR.AtomType{value: :expr_2}
                     ]
                   },
                   pattern: %IR.IntegerType{value: 1}
                 },
                 %{
                   bindings: [],
                   body: %IR.Block{
                     expressions: [
                       %IR.AtomType{value: :expr_3},
                       %IR.AtomType{value: :expr_4}
                     ]
                   },
                   pattern: %IR.IntegerType{value: 2}
                 }
               ]
             }
    end

    test "clause with bindings" do
      # case x do
      #   %{a: a} -> :ok
      # end
      ast =
        {:case, [line: 1],
         [
           {:x, [line: 1], nil},
           [
             do: [
               {:->, [line: 2],
                [
                  [{:%{}, [line: 2], [a: {:a, [line: 2], nil}]}],
                  {:__block__, [], [:ok]}
                ]}
             ]
           ]
         ]}

      assert transform(ast) == %IR.CaseExpression{
               condition: %IR.Symbol{name: :x},
               clauses: [
                 %{
                   bindings: [
                     %IR.Binding{
                       name: :a,
                       access_path: [
                         %IR.CaseConditionAccess{},
                         %IR.MapAccess{
                           key: %IR.AtomType{value: :a}
                         }
                       ]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [
                       %IR.AtomType{value: :ok}
                     ]
                   },
                   pattern: %IR.MapType{
                     data: [
                       {%IR.AtomType{value: :a}, %IR.Symbol{name: :a}}
                     ]
                   }
                 }
               ]
             }
    end
  end

  describe "for expression" do
    test "single generator, single binding" do
      # for n <- [1, 2], do: n * n
      ast =
        {:for, [line: 1],
         [
           {:<-, [line: 1], [{:n, [line: 1], nil}, [1, 2]]},
           [
             do: {:__block__, [], [{:*, [line: 1], [{:n, [line: 1], nil}, {:n, [line: 1], nil}]}]}
           ]
         ]}

      # Enum.reduce([1, 2], [], fn holo_el__, holo_acc__ ->
      #   n = holo_el__
      #   holo_acc__ ++ [n * n]
      # end)
      assert transform(ast) == %IR.Call{
               module: %IR.Alias{segments: [:Enum]},
               function: :reduce,
               args: [
                 %IR.ListType{
                   data: [
                     %IR.IntegerType{value: 1},
                     %IR.IntegerType{value: 2}
                   ]
                 },
                 %IR.ListType{data: []},
                 %IR.AnonymousFunctionType{
                   arity: 2,
                   params: [
                     %IR.Symbol{name: :holo_el__},
                     %IR.Symbol{name: :holo_acc__}
                   ],
                   bindings: [
                     %IR.Binding{
                       name: :holo_acc__,
                       access_path: [%IR.ParamAccess{index: 1}]
                     },
                     %IR.Binding{
                       name: :holo_el__,
                       access_path: [%IR.ParamAccess{index: 0}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [
                       %IR.MatchOperator{
                         bindings: [
                           %IR.Binding{
                             name: :n,
                             access_path: [%IR.MatchAccess{}]
                           }
                         ],
                         left: %IR.Symbol{name: :n},
                         right: %IR.Symbol{name: :holo_el__}
                       },
                       %IR.ListConcatenationOperator{
                         left: %IR.Symbol{name: :holo_acc__},
                         right: %IR.ListType{
                           data: [
                             %IR.MultiplicationOperator{
                               left: %IR.Symbol{name: :n},
                               right: %IR.Symbol{name: :n}
                             }
                           ]
                         }
                       }
                     ]
                   }
                 }
               ]
             }
    end

    test "multiple generators" do
      # for n <- [1, 2], m <- [3, 4], do: n * m
      ast =
        {:for, [line: 1],
         [
           {:<-, [line: 1], [{:n, [line: 1], nil}, [1, 2]]},
           {:<-, [line: 1], [{:m, [line: 1], nil}, [3, 4]]},
           [
             do: {:__block__, [], [{:*, [line: 1], [{:n, [line: 1], nil}, {:m, [line: 1], nil}]}]}
           ]
         ]}

      # Enum.reduce([1, 2], [], fn holo_el__, holo_acc__ ->
      #   n = holo_el__
      #   holo_acc__ ++ Enum.reduce([3, 4], [], fn holo_el__, holo_acc__ ->
      #     m = holo_el__
      #     holo_acc__ ++ [n * m]
      #   end)
      # end)
      assert transform(ast) == %IR.Call{
               module: %IR.Alias{segments: [:Enum]},
               function: :reduce,
               args: [
                 %IR.ListType{
                   data: [
                     %IR.IntegerType{value: 1},
                     %IR.IntegerType{value: 2}
                   ]
                 },
                 %IR.ListType{data: []},
                 %IR.AnonymousFunctionType{
                   arity: 2,
                   params: [
                     %IR.Symbol{name: :holo_el__},
                     %IR.Symbol{name: :holo_acc__}
                   ],
                   bindings: [
                     %IR.Binding{
                       name: :holo_acc__,
                       access_path: [%IR.ParamAccess{index: 1}]
                     },
                     %IR.Binding{
                       name: :holo_el__,
                       access_path: [%IR.ParamAccess{index: 0}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [
                       %IR.MatchOperator{
                         bindings: [
                           %IR.Binding{
                             name: :n,
                             access_path: [%IR.MatchAccess{}]
                           }
                         ],
                         left: %IR.Symbol{name: :n},
                         right: %IR.Symbol{name: :holo_el__}
                       },
                       %IR.ListConcatenationOperator{
                         left: %IR.Symbol{name: :holo_acc__},
                         right: %IR.Call{
                           module: %IR.Alias{segments: [:Enum]},
                           function: :reduce,
                           args: [
                             %IR.ListType{
                               data: [
                                 %IR.IntegerType{value: 3},
                                 %IR.IntegerType{value: 4}
                               ]
                             },
                             %IR.ListType{data: []},
                             %IR.AnonymousFunctionType{
                               arity: 2,
                               params: [
                                 %IR.Symbol{name: :holo_el__},
                                 %IR.Symbol{name: :holo_acc__}
                               ],
                               bindings: [
                                 %IR.Binding{
                                   name: :holo_acc__,
                                   access_path: [%IR.ParamAccess{index: 1}]
                                 },
                                 %IR.Binding{
                                   name: :holo_el__,
                                   access_path: [%IR.ParamAccess{index: 0}]
                                 }
                               ],
                               body: %IR.Block{
                                 expressions: [
                                   %IR.MatchOperator{
                                     bindings: [
                                       %IR.Binding{
                                         name: :m,
                                         access_path: [%IR.MatchAccess{}]
                                       }
                                     ],
                                     left: %IR.Symbol{name: :m},
                                     right: %IR.Symbol{name: :holo_el__}
                                   },
                                   %IR.ListConcatenationOperator{
                                     left: %IR.Symbol{name: :holo_acc__},
                                     right: %IR.ListType{
                                       data: [
                                         %IR.MultiplicationOperator{
                                           left: %IR.Symbol{name: :n},
                                           right: %IR.Symbol{name: :m}
                                         }
                                       ]
                                     }
                                   }
                                 ]
                               }
                             }
                           ]
                         }
                       }
                     ]
                   }
                 }
               ]
             }
    end

    test "single generator, multiple bindings" do
      # for {a, b} <- [{1, 2}, {3, 4}], do: a * b
      ast =
        {:for, [line: 1],
         [
           {:<-, [line: 1], [{{:a, [line: 1], nil}, {:b, [line: 1], nil}}, [{1, 2}, {3, 4}]]},
           [
             do: {:__block__, [], [{:*, [line: 1], [{:a, [line: 1], nil}, {:b, [line: 1], nil}]}]}
           ]
         ]}

      # Enum.reduce([{1, 2}, {3, 4}], [], fn holo_el__, holo_acc__ ->
      #   {a, b} = holo_el__
      #   holo_acc__ ++ [a * b]
      # end)
      assert transform(ast) == %IR.Call{
               module: %IR.Alias{segments: [:Enum]},
               function: :reduce,
               args: [
                 %IR.ListType{
                   data: [
                     %IR.TupleType{
                       data: [
                         %IR.IntegerType{value: 1},
                         %IR.IntegerType{value: 2}
                       ]
                     },
                     %IR.TupleType{
                       data: [
                         %IR.IntegerType{value: 3},
                         %IR.IntegerType{value: 4}
                       ]
                     }
                   ]
                 },
                 %IR.ListType{data: []},
                 %IR.AnonymousFunctionType{
                   arity: 2,
                   params: [
                     %IR.Symbol{name: :holo_el__},
                     %IR.Symbol{name: :holo_acc__}
                   ],
                   bindings: [
                     %IR.Binding{
                       name: :holo_acc__,
                       access_path: [%IR.ParamAccess{index: 1}]
                     },
                     %IR.Binding{
                       name: :holo_el__,
                       access_path: [%IR.ParamAccess{index: 0}]
                     }
                   ],
                   body: %IR.Block{
                     expressions: [
                       %IR.MatchOperator{
                         bindings: [
                           %IR.Binding{
                             name: :a,
                             access_path: [
                               %IR.MatchAccess{},
                               %IR.TupleAccess{index: 0}
                             ]
                           },
                           %IR.Binding{
                             name: :b,
                             access_path: [
                               %IR.MatchAccess{},
                               %IR.TupleAccess{index: 1}
                             ]
                           }
                         ],
                         left: %IR.TupleType{
                           data: [
                             %IR.Symbol{name: :a},
                             %IR.Symbol{name: :b}
                           ]
                         },
                         right: %IR.Symbol{name: :holo_el__}
                       },
                       %IR.ListConcatenationOperator{
                         left: %IR.Symbol{name: :holo_acc__},
                         right: %IR.ListType{
                           data: [
                             %IR.MultiplicationOperator{
                               left: %IR.Symbol{name: :a},
                               right: %IR.Symbol{name: :b}
                             }
                           ]
                         }
                       }
                     ]
                   }
                 }
               ]
             }
    end
  end

  test "if expression" do
    # if true do
    #   1
    #   2
    # else
    #   3
    #   4
    # end
    ast = {:if, [line: 1], [true, [do: {:__block__, [], [1, 2]}, else: {:__block__, [], [3, 4]}]]}

    assert transform(ast) == %IR.IfExpression{
             condition: %IR.BooleanType{value: true},
             do: %IR.Block{
               expressions: [
                 %IR.IntegerType{value: 1},
                 %IR.IntegerType{value: 2}
               ]
             },
             else: %IR.Block{
               expressions: [
                 %IR.IntegerType{value: 3},
                 %IR.IntegerType{value: 4}
               ]
             }
           }
  end

  test "public macro definition" do
    # defmacro my_macro do
    #   quote do
    #     123
    #   end
    # end
    ast =
      {:defmacro, [line: 1],
       [
         {:my_macro, [line: 1], nil},
         [do: {:__block__, [], [{:quote, [line: 2], [[do: {:__block__, [], [123]}]]}]}]
       ]}

    assert transform(ast) == %IR.IgnoredExpression{type: :public_macro_definition}
  end

  test "symbol" do
    # a
    ast = {:a, [line: 1], nil}

    assert transform(ast) == %IR.Symbol{name: :a}
  end
end
