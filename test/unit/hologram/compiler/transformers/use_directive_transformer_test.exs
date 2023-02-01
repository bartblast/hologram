defmodule Hologram.Compiler.UseDirectiveTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.UseDirective
  alias Hologram.Compiler.UseDirectiveTransformer

  test "use directive without opts" do
    code = "use Abc.Bcd"
    ast = ast(code)

    result = UseDirectiveTransformer.transform(ast)
    expected = %UseDirective{alias_segs: [:Abc, :Bcd], opts: []}

    assert result == expected
  end

  test "use directive with opts" do
    code = "use Abc.Bcd, a: 1, b: 2"
    ast = ast(code)

    result = UseDirectiveTransformer.transform(ast)

    opts = [a: 1, b: 2]
    expected = %UseDirective{alias_segs: [:Abc, :Bcd], opts: opts}

    assert result == expected
  end
end
