defmodule Hologram.Compiler.IRTest do
  use Hologram.Test.BasicCase, async: true
  alias Hologram.Compiler.IR

  test "for_code/1" do
    assert IR.for_code("1 + 2") == %IR.AdditionOperator{
             left: %IR.IntegerType{value: 1},
             right: %IR.IntegerType{value: 2}
           }
  end
end
