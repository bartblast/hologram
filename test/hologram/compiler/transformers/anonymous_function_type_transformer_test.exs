defmodule Hologram.Compiler.AnonymousFunctionTypeTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.{AnonymousFunctionTypeTransformer, Context}

  alias Hologram.Compiler.IR.{
    AccessOperator,
    AnonymousFunctionType,
    AtomType,
    IntegerType,
    Variable
  }

  test "arity" do
    code = "fn 1, 2 -> 9 end"
    ast = ast(code)

    assert %AnonymousFunctionType{arity: 2} =
             AnonymousFunctionTypeTransformer.transform(ast, %Context{})
  end

  test "params" do
    code = "fn a, b -> 9 end"
    ast = ast(code)

    assert %AnonymousFunctionType{} =
             result = AnonymousFunctionTypeTransformer.transform(ast, %Context{})

    expected = [
      %Variable{name: :a},
      %Variable{name: :b}
    ]

    assert result.params == expected
  end

  test "bindings" do
    code = "fn 1, %{a: x, b: y} -> 9 end"
    ast = ast(code)

    assert %AnonymousFunctionType{} =
             result = AnonymousFunctionTypeTransformer.transform(ast, %Context{})

    expected = [
      x:
        {1,
         [
           %AccessOperator{
             key: %AtomType{value: :a}
           },
           %Variable{name: :x}
         ]},
      y:
        {1,
         [
           %AccessOperator{
             key: %AtomType{value: :b}
           },
           %Variable{name: :y}
         ]}
    ]

    assert result.bindings == expected
  end

  test "body, single expression" do
    code = "fn -> 1 end"
    ast = ast(code)

    assert %AnonymousFunctionType{} =
             result = AnonymousFunctionTypeTransformer.transform(ast, %Context{})

    assert result.body == [%IntegerType{value: 1}]
  end

  test "body, multiple expressions" do
    code = """
    fn ->
      1
      2
    end
    """

    ast = ast(code)

    assert %AnonymousFunctionType{} =
             result = AnonymousFunctionTypeTransformer.transform(ast, %Context{})

    expected = [
      %IntegerType{value: 1},
      %IntegerType{value: 2}
    ]

    assert result.body == expected
  end
end
