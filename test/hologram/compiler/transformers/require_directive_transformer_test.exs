defmodule Hologram.Compiler.RequireDirectiveTransformerTest do
  use Hologram.TestCase, async: true

  alias Hologram.Compiler.IR.RequireDirective
  alias Hologram.Compiler.RequireDirectiveTransformer

  test "transform/1" do
    code = "require Hologram.Test.Fixtures.Compiler.Transformer.Module1"
    {:require, _, ast} = ast(code)

    result = RequireDirectiveTransformer.transform(ast)
    expected = %RequireDirective{module: Hologram.Test.Fixtures.Compiler.Transformer.Module1}

    assert result == expected
  end
end
