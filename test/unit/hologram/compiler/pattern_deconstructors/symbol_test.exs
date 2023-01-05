defmodule Hologram.Compiler.PatternDeconstructor.SymbolTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.IR.Symbol
  alias Hologram.Compiler.PatternDeconstructor

  test "deconstruct/2" do
    ir = %Symbol{name: :test}
    result = PatternDeconstructor.deconstruct(ir)
    expected = [[%Symbol{name: :test}]]

    assert result == expected
  end
end
