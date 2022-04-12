defmodule Hologram.Compiler.PatternDeconstructor.FallbackTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.IR.IntegerType
  alias Hologram.Compiler.PatternDeconstructor

  test "deconstruct/2" do
    ir = %IntegerType{value: 1}

    assert PatternDeconstructor.deconstruct(ir) == []
  end
end
