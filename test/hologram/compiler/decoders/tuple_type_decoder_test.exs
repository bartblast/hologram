defmodule Hologram.Compiler.TupleTypeDecoderTest do
  use Hologram.TestCase, async: true
  alias Hologram.Compiler.TupleTypeDecoder

  test "decode/1" do
    input = [
      %{"type" => "integer", "value" => 1},
      %{"type" => "atom", "value" => "test"}
    ]

    result = TupleTypeDecoder.decode(input)
    expected = {1, :test}

    assert result == expected
  end
end
