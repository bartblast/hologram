defmodule Hologram.Compiler.ListTypeDecoderTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Compiler.ListTypeDecoder

  test "decode/1" do
    value = %{
      "type" => "list",
      "data" => [
        %{"type" => "integer", "value" => 1},
        %{"type" => "atom", "value" => "test"}
      ]
    }

    result = ListTypeDecoder.decode(value)
    expected = [1, :test]

    assert result == expected
  end
end
