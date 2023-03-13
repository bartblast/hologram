defmodule Hologram.Compiler.TupleTypeDecoderTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Compiler.TupleTypeDecoder

  test "encoded tuple decoding" do
    value = %{
      "type" => "tuple",
      "data" => [
        %{"type" => "integer", "value" => 1},
        %{"type" => "atom", "value" => "test"}
      ]
    }

    result = TupleTypeDecoder.decode(value)
    expected = {1, :test}

    assert result == expected
  end
end
