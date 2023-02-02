defmodule Hologram.Compiler.UseDirectiveTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR
  alias Hologram.Compiler.UseDirectiveTransformer

  test "use directive without opts" do
    code = "use Abc.Bcd"
    ast = ast(code)

    result = UseDirectiveTransformer.transform(ast)
    expected = %IR.UseDirective{alias_segs: [:Abc, :Bcd], opts: []}

    assert result == expected
  end

  test "use directive with opts" do
    code = "use Abc.Bcd, a: 1, b: 2"
    ast = ast(code)

    result = UseDirectiveTransformer.transform(ast)

    expected_opts = [a: %IR.IntegerType{value: 1}, b: %IR.IntegerType{value: 2}]
    expected = %IR.UseDirective{alias_segs: [:Abc, :Bcd], opts: expected_opts}

    assert result == expected
  end
end
