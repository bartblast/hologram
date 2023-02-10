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
end
