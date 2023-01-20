defmodule Hologram.Compiler.ModuleAttributeEvaluatorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Context
  alias Hologram.Compiler.ModuleAttributeEvaluator

  @context %Context{module_attributes: %{a: 1, b: 2, c: 3}}

  test "expression which doesn't use module attributes" do
    code = "5 + 6"
    ast = ast(code)
    result = ModuleAttributeEvaluator.evaluate(ast, @context)

    assert result == 11
  end

  test "expression which uses module attributes" do
    code = "@a + @c"
    ast = ast(code)
    result = ModuleAttributeEvaluator.evaluate(ast, @context)

    assert result == 4
  end
end
