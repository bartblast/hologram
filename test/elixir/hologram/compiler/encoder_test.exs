defmodule Hologram.Compiler.EncoderTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Encoder
  alias Hologram.Compiler.IR

  test "atom type" do
    assert encode(%IR.AtomType{value: :"aa'bb\ncc"}) == "{type: 'atom', value: 'aa\\'bb\\ncc'}"
  end

  test "float type" do
    assert encode(%IR.FloatType{value: 1.23}) == "{type: 'float', value: 1.23}"
  end

  test "integer type" do
    assert encode(%IR.IntegerType{value: 123}) == "{type: 'integer', value: 123}"
  end

  test "string type" do
    assert encode(%IR.StringType{value: "aa'bb\ncc"}) == "{type: 'atom', value: 'aa\\'bb\\ncc'}"
  end
end
