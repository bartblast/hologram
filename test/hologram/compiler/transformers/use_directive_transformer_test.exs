defmodule Hologram.Compiler.UseDirectiveTransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.IR.UseDirective
  alias Hologram.Compiler.UseDirectiveTransformer

  test "transform/1" do
    module_segs = [:Hologram, :Compiler, :UseDirectiveTransformerTest]

    result = UseDirectiveTransformer.transform(module_segs)
    expected = %UseDirective{module: Hologram.Compiler.UseDirectiveTransformerTest}

    assert result == expected
  end
end
