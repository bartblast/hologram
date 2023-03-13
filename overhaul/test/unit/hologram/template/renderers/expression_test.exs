defmodule Hologram.Template.Renderer.ExpressionTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.ModuleAttributeOperator
  alias Hologram.Compiler.IR.TupleType
  alias Hologram.Conn
  alias Hologram.Template.Renderer
  alias Hologram.Template.VDOM.Expression

  test "render/4" do
    expression = %Expression{
      ir: %TupleType{
        data: [%ModuleAttributeOperator{name: :a}]
      }
    }

    bindings = %{a: 123}

    result = Renderer.render(expression, %Conn{}, bindings)
    expected = {"123", %{}}

    assert result == expected
  end
end
