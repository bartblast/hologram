defmodule Hologram.Compiler.PatternDeconstructor.VariableTest do
  use Hologram.Test.UnitCase, async: false

  alias Hologram.Compiler.IR.Variable
  alias Hologram.Compiler.PatternDeconstructor

  test "deconstruct/2" do
    ir = %Variable{name: :test}
    result = PatternDeconstructor.deconstruct(ir)
    expected = [[%Variable{name: :test}]]

    assert result == expected
  end
end
