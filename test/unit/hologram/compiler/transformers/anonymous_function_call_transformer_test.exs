defmodule Hologram.Compiler.AnonymousFunctionCallTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.AnonymousFunctionCallTransformer
  alias Hologram.Compiler.IR.AnonymousFunctionCall
  alias Hologram.Compiler.IR.IntegerType

  test "function without params" do
    code = "test.()"
    ast = ast(code)
    result = AnonymousFunctionCallTransformer.transform(ast)

    expected = %AnonymousFunctionCall{
      name: :test,
      args: []
    }

    assert result == expected
  end

  test "function with params" do
    code = "test.(1, 2)"
    ast = ast(code)
    result = AnonymousFunctionCallTransformer.transform(ast)

    expected = %AnonymousFunctionCall{
      name: :test,
      args: [
        %IntegerType{value: 1},
        %IntegerType{value: 2}
      ]
    }

    assert result == expected
  end
end
