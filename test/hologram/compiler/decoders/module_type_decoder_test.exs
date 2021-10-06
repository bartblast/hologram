defmodule Hologram.Compiler.ModuleTypeDecoderTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Compiler.ModuleTypeDecoder

  test "encoded module decoding" do
    value = %{
      "type" => "module",
      "className" => "Elixir_Hologram_Compiler_ModuleTypeDecoderTest"
    }

    result = ModuleTypeDecoder.decode(value)
    expected = Hologram.Compiler.ModuleTypeDecoderTest

    assert result == expected
  end
end
