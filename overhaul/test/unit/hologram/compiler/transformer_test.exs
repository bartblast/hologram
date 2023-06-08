defmodule Hologram.Compiler.TransformerTest do
  use Hologram.Test.UnitCase, async: true
  import Hologram.Compiler.Transformer

  # --- OPERATORS ---

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
end
