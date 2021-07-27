defmodule Hologram.Compiler.ListTypeDecoderTest do
  use Hologram.TestCase, async: true
  alias Hologram.Compiler.ListTypeDecoder

  test "empty list" do
    input = []
    result = ListTypeDecoder.decode(input)

    assert result == []
  end

  test "non-empty, not-nested list" do
    input = [
      %{"type" => "integer", "value" => 1},
      %{"type" => "atom", "value" => "test"}
    ]

    result = ListTypeDecoder.decode(input)
    expected = [1, :test]

    assert result == expected
  end

  test "nested list" do
    input = [
      %{"type" => "integer", "value" => 1},
      %{
        "type" => "list",
        "data" => [
          %{"type" => "integer", "value" => 2},
          %{"type" => "integer", "value" => 3}
        ]
      }
    ]

    result = ListTypeDecoder.decode(input)
    expected = [1, [2, 3]]

    assert result == expected
  end
end
