defmodule Hologram.Compiler.DetransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Detransformer
  alias Hologram.Compiler.IR

  test "integer type" do
    ir = %IR.IntegerType{value: 123}
    result = Detransformer.detransform(ir)
    assert result == 123
  end
end
