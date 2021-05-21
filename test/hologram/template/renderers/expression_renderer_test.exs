defmodule Hologram.Template.ExpressionRendererTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.ModuleAttributeOperator
  alias Hologram.Template.ExpressionRenderer

  test "render/2" do
    ir = %ModuleAttributeOperator{name: :a}
    state = %{a: 123}

    result = ExpressionRenderer.render(ir, state)
    expected = "123"

    assert result == expected
  end
end
