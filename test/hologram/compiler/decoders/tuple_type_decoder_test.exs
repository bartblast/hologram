defmodule Hologram.Compiler.TupleTypeDecoderTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Compiler.TupleTypeDecoder

  test "decode/1" do
    data = [
      %{"type" => "integer", "value" => 1},
      %{"type" => "atom", "value" => "test"}
    ]

    result = TupleTypeDecoder.decode(data)
    expected = {1, :test}

    assert result == expected
  end
end
