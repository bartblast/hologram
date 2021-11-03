defmodule Hologram.Template.Renderer.ExpressionTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.{ModuleAttributeOperator, TupleType}
  alias Hologram.Template.VDOM.Expression
  alias Hologram.Template.Renderer

  test "render/2" do
    expression = %Expression{
      ir: %TupleType{
        data: [%ModuleAttributeOperator{name: :a}]
      }
    }

    bindings = %{a: 123}

    result = Renderer.render(expression, bindings)
    expected = "123"

    assert result == expected
  end
end
