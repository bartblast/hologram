defmodule Hologram.Compiler.TupleTypeDecoderTest do
  use Hologram.TestCase, async: true
  alias Hologram.Compiler.TupleTypeDecoder

  test "empty tuple" do
    input = []
    result = TupleTypeDecoder.decode(input)

    assert result == {}
  end

  test "non-empty, not-nested tuple" do
    input = [
      %{"type" => "integer", "value" => 1},
      %{"type" => "atom", "value" => "test"}
    ]

    result = TupleTypeDecoder.decode(input)
    expected = {1, :test}

    assert result == expected
  end

  test "nested tuple" do
    input = [
      %{"type" => "integer", "value" => 1},
      %{
        "type" => "tuple",
        "data" => [
          %{"type" => "integer", "value" => 2},
          %{"type" => "integer", "value" => 3}
        ]
      }
    ]

    result = TupleTypeDecoder.decode(input)
    expected = {1, {2, 3}}

    assert result == expected
  end
end
