defmodule Hologram.Compiler.RequireDirectiveTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.RequireDirective
  alias Hologram.Compiler.RequireDirectiveTransformer

  test "transform/1" do
    code = "require Hologram.Test.Fixtures.Compiler.Transformer.Module1"
    ast = ast(code)

    result = RequireDirectiveTransformer.transform(ast)
    expected = %RequireDirective{module: Hologram.Test.Fixtures.Compiler.Transformer.Module1}

    assert result == expected
  end
end
