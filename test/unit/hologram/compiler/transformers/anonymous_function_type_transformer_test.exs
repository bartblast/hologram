defmodule Hologram.Compiler.AnonymousFunctionTypeTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.AnonymousFunctionTypeTransformer

  alias Hologram.Compiler.IR.{
    AnonymousFunctionType,
    AtomType,
    Binding,
    Block,
    IntegerType,
    MapAccess,
    NotSupportedExpression,
    ParamAccess,
    Variable
  }

  test "arity" do
    code = "fn 1, 2 -> 9 end"
    ast = ast(code)

    assert %AnonymousFunctionType{arity: 2} = AnonymousFunctionTypeTransformer.transform(ast)
  end

  test "params" do
    code = "fn a, b -> 9 end"
    ast = ast(code)

    assert %AnonymousFunctionType{} = result = AnonymousFunctionTypeTransformer.transform(ast)

    expected = [
      %Variable{name: :a},
      %Variable{name: :b}
    ]

    assert result.params == expected
  end

  test "bindings" do
    code = "fn 1, %{a: x, b: y} -> 9 end"
    ast = ast(code)

    assert %AnonymousFunctionType{} = result = AnonymousFunctionTypeTransformer.transform(ast)

    expected = [
      %Binding{
        name: :x,
        access_path: [
          %ParamAccess{index: 1},
          %MapAccess{key: %AtomType{value: :a}}
        ]
      },
      %Binding{
        name: :y,
        access_path: [
          %ParamAccess{index: 1},
          %MapAccess{key: %AtomType{value: :b}}
        ]
      }
    ]

    assert result.bindings == expected
  end

  test "body, single expression" do
    code = "fn -> 1 end"
    ast = ast(code)

    assert %AnonymousFunctionType{} = result = AnonymousFunctionTypeTransformer.transform(ast)

    assert result.body == %Block{expressions: [%IntegerType{value: 1}]}
  end

  test "body, multiple expressions" do
    code = """
    fn ->
      1
      2
    end
    """

    ast = ast(code)

    assert %AnonymousFunctionType{} = result = AnonymousFunctionTypeTransformer.transform(ast)

    expected = %Block{
      expressions: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ]
    }

    assert result.body == expected
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
    result = AnonymousFunctionTypeTransformer.transform(ast)
    expected = %NotSupportedExpression{ast: ast, type: :multi_clause_anonymous_function_type}

    assert result == expected
  end
end
