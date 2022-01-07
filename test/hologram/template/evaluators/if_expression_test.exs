defmodule Hologram.Template.Evaluator.IfExpressionTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.{BooleanType, IfExpression, Variable}
  alias Hologram.Template.Evaluator

  @bindings %{a: 1, b: 2}

  test "evaluates do expression" do
    ir = %IfExpression{
      condition: %BooleanType{value: true},
      do: %Variable{name: :a},
      else: %Variable{name: :b}
    }

    result = Evaluator.evaluate(ir, @bindings)
    expected = 1

    assert result == expected
  end

  test "evaluates else expression" do
    ir = %IfExpression{
      condition: %BooleanType{value: false},
      do: %Variable{name: :a},
      else: %Variable{name: :b}
    }

    result = Evaluator.evaluate(ir, @bindings)
    expected = 2

    assert result == expected
  end
end
