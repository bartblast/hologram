defmodule Hologram.Compiler.TransformerTest do
  use Hologram.Test.UnitCase, async: true
  import Hologram.Compiler.Transformer
  alias Hologram.Compiler.IR

  # --- DATA TYPES --

  describe "anonymous function type" do
    test "arity" do
      ast = ast("fn 1, 2 -> 9 end")
      assert %IR.AnonymousFunctionType{arity: 2} = transform(ast)
    end

    test "params" do
      ast = ast("fn a, b -> 9 end")

      assert %IR.AnonymousFunctionType{
               params: [
                 %IR.Variable{name: :a},
                 %IR.Variable{name: :b}
               ]
             } = transform(ast)
    end

    test "bindings" do
      ast = ast("fn 1, %{a: x, b: y} -> 9 end")

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
      ast = ast("fn -> 1 end")

      assert %IR.AnonymousFunctionType{body: %IR.Block{expressions: [%IR.IntegerType{value: 1}]}} =
               transform(ast)
    end

    test "body, multiple expressions" do
      code = """
      fn ->
        1
        2
      end
      """

      ast = ast(code)

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
      code = """
      fn
        1 -> :a
        2 -> :b
      end
      """

      ast = ast(code)

      assert transform(ast) == %IR.NotSupportedExpression{
               type: :multi_clause_anonymous_function_type,
               ast: ast
             }
    end
  end

  test "boolean type" do
    ast = ast("true")
    assert transform(ast) == %IR.BooleanType{value: true}
  end

  test "float type" do
    ast = ast("1.0")
    assert transform(ast) == %IR.FloatType{value: 1.0}
  end

  test "integer type" do
    ast = ast("1")
    assert transform(ast) == %IR.IntegerType{value: 1}
  end

  test "nil type" do
    ast = ast("nil")
    assert transform(ast) == %IR.NilType{}
  end

  test "string type" do
    ast = ast(~s("test"))
    assert transform(ast) == %IR.StringType{value: "test"}
  end

  # --- OTHER IR ---

  test "alias" do
    # A.B
    ast = {:__aliases__, [line: 1], [:A, :B]}

    assert transform(ast) == %IR.Alias{segments: [:A, :B]}
  end

  test "block" do
    ast = {:__block__, [], [1, 2]}

    assert transform(ast) == %IR.Block{
             expressions: [
               %IR.IntegerType{value: 1},
               %IR.IntegerType{value: 2}
             ]
           }
  end

  test "symbol" do
    ast = ast("a")
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
               %IR.Variable{name: :a},
               %IR.Variable{name: :b}
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
