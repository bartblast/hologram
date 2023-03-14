defmodule Hologram.Compiler.PatternMatchingTest do
  use Hologram.Test.UnitCase, async: true
  import Hologram.Compiler.PatternMatching
  alias Hologram.Compiler.IR

  test "binding" do
    ir = %IR.Symbol{name: :a}

    assert deconstruct(ir, :left) == [[binding: :a]]
  end

  test "left value" do
    ir = %IR.IntegerType{value: 1}

    assert deconstruct(ir, :left) == [[left_value: %IR.IntegerType{value: 1}]]
  end

  test "right value from literal value" do
    ir = %IR.IntegerType{value: 1}

    assert deconstruct(ir, :right) == [[:right_value]]
  end

  test "right value from variable" do
    ir = %IR.Symbol{name: :a}

    assert deconstruct(ir, :right) == [[:right_value]]
  end
end
