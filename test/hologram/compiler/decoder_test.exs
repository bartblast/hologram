defmodule Hologram.Compiler.DecoderTest do
  use Hologram.TestCase, async: true
  alias Hologram.Compiler.Decoder

  test "atom" do
    input = %{"type" => "atom", "value" => "test"}
    assert Decoder.decode(input) == :test
  end

  test "integer" do
    input = %{"type" => "integer", "value" => 1}
    assert Decoder.decode(input) == 1
  end

  test "list" do
    input = %{
      "type" => "list",
      "data" => [
        %{"type" => "integer", "value" => 1},
        %{"type" => "integer", "value" => 2}
      ]
    }

    assert Decoder.decode(input) == [1, 2]
  end

  test "map" do
    input =
      %{
        "type" => "map",
        "data" => %{
          "~string[test_key]" => %{
            "type" => "string",
            "value" => "test_value"
          }
        }
      }

    result = Decoder.decode(input)
    expected = %{"test_key" => "test_value"}

    assert result == expected
  end

  test "string" do
    input = %{"type" => "string", "value" => "test"}
    assert Decoder.decode(input) == "test"
  end
end
