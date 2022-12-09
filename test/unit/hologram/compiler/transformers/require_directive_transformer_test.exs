defmodule Hologram.Compiler.RequireDirectiveTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.RequireDirective
  alias Hologram.Compiler.RequireDirectiveTransformer

  test "transform/1" do
    code = "require Abc.Bcd"
    ast = ast(code)

    result = RequireDirectiveTransformer.transform(ast)
    expected = %RequireDirective{alias_segs: [:Abc, :Bcd], module: nil}

    assert result == expected
  end
end
