defmodule Hologram.Compiler.IRTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.IR

  alias Hologram.Compiler.Context
  alias Hologram.Compiler.IR

  test "for_code/1" do
    assert for_code("[1, :b]", %Context{}) == %IR.ListType{
             data: [
               %IR.IntegerType{value: 1},
               %IR.AtomType{value: :b}
             ]
           }
  end
end
