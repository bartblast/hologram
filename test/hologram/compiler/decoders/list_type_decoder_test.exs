defmodule Hologram.Compiler.ListTypeDecoderTest do
  use Hologram.TestCase, async: true
  alias Hologram.Compiler.ListTypeDecoder

  test "decode/1" do
    input = [
      %{"type" => "integer", "value" => 1},
      %{"type" => "atom", "value" => "test"}
    ]

    result = ListTypeDecoder.decode(input)
    expected = [1, :test]

    assert result == expected
  end
end
