defmodule Hologram.Compiler.UseDirectiveTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.UseDirective
  alias Hologram.Compiler.UseDirectiveTransformer

  test "transform/1" do
    code = "use Hologram.Compiler.UseDirectiveTransformerTest"
    ast = ast(code)

    result = UseDirectiveTransformer.transform(ast)
    expected = %UseDirective{module: Hologram.Compiler.UseDirectiveTransformerTest}

    assert result == expected
  end
end
