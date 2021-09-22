defmodule Hologram.Template.ExpressionRendererTest do
  use Hologram.Test.UnitCase , async: true

  alias Hologram.Compiler.IR.{ModuleAttributeOperator, TupleType}
  alias Hologram.Template.Document.Expression
  alias Hologram.Template.Renderer

  test "render/2" do
    expression =
      %Expression{
        ir: %TupleType{
          data: [%ModuleAttributeOperator{name: :a}]
        }
      }

    state = %{a: 123}

    result = Renderer.render(expression, state)
    expected = "123"

    assert result == expected
  end
end
