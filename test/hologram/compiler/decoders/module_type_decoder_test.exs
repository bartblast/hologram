defmodule Hologram.Compiler.ModuleTypeDecoderTest do
  use Hologram.Test.UnitCase , async: true
  alias Hologram.Compiler.ModuleTypeDecoder

  test "decode/1" do
    class = "Elixir_Hologram_Compiler_ModuleTypeDecoderTest"

    result = ModuleTypeDecoder.decode(class)
    expected = Hologram.Compiler.ModuleTypeDecoderTest

    assert result == expected
  end
end
