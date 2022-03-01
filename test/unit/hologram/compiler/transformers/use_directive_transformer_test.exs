defmodule Hologram.Compiler.UseDirectiveTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.UseDirective
  alias Hologram.Compiler.UseDirectiveTransformer

  @module Hologram.Compiler.UseDirectiveTransformerTest

  test "use directive without opts" do
    code = "use Hologram.Compiler.UseDirectiveTransformerTest"
    ast = ast(code)

    result = UseDirectiveTransformer.transform(ast)
    expected = %UseDirective{module: @module, opts: []}

    assert result == expected
  end

  test "use directive with opts" do
    code = "use Hologram.Compiler.UseDirectiveTransformerTest, a: 1, b: 2"
    ast = ast(code)

    result = UseDirectiveTransformer.transform(ast)

    opts = [a: 1, b: 2]
    expected = %UseDirective{module: @module, opts: opts}

    assert result == expected
  end
end
