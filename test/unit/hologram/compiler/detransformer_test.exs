defmodule Hologram.Compiler.DetransformerTest do
  use Hologram.Test.UnitCase, async: true

  alias Hologram.Compiler.Detransformer
  alias Hologram.Compiler.IR

  test "integer type" do
    ir = %IR.IntegerType{value: 123}
    result = Detransformer.detransform(ir)
    assert result == 123
  end

  test "variable" do
    ir = %IR.Variable{name: :test}
    result = Detransformer.detransform(ir)
    assert result == {:test, [], nil}
  end
end
