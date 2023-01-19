defmodule Hologram.Compiler.ModuleAttributeEvaluatorTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Context
  alias Hologram.Compiler.ModuleAttributeEvaluator

  @context %Context{module_attributes: %{a: 1, b: 2, c: 3}}

  test "expression which doesn't use other module_attributes" do
    code = "5 + 6"
    ast = ast(code)
    result = ModuleAttributeEvaluator.evaluate(ast, @context)

    assert result == 11
  end

  test "expression which uses other module attributes" do
    code = "@a + @c"
    ast = ast(code)
    result = ModuleAttributeEvaluator.evaluate(ast, @context)

    assert result == 4
  end

  # test "evaluated if expression" do
  #   code = "if @a, do: @b, else: @c"
  #   ast = ast(code)
  #   result = Evaluator.evaluate(ast, @bindings)

  #   assert result == 2
  # end

  # test "injects bindings key into bindings" do
  #   code = "1 + @bindings.c"
  #   ast = ast(code)
  #   result = Evaluator.evaluate(ast, @bindings)

  #   assert result == 4
  # end
end
