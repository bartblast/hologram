defmodule Hologram.Compiler.EncoderTest do
  use Hologram.Test.BasicCase, async: true
  import Hologram.Compiler.Encoder
  alias Hologram.Compiler.IR

  test "integer type" do
    assert encode(%IR.IntegerType{value: 123}) == "{type: 'integer', value: 123}"
  end
end
