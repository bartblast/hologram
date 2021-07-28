defmodule Hologram.Compiler.MapTypeDecoderTest do
  use Hologram.TestCase, async: true
  alias Hologram.Compiler.MapTypeDecoder

  test "decode/1" do
    input = %{
      "~string[test_key]" => %{
        "type" => "string",
        "value" => "test_value"
      }
    }

    result = MapTypeDecoder.decode(input)
    expected = %{"test_key" => "test_value"}

    assert result == expected
  end

  test "atom key" do
    input = %{
      "~atom[test_key]" => %{
        "type" => "string",
        "value" => "test_value"
      }
    }

    result = MapTypeDecoder.decode(input)
    expected = %{test_key: "test_value"}

    assert result == expected
  end

  test "string key" do
    input = %{
      "~string[test_key]" => %{
        "type" => "string",
        "value" => "test_value"
      }
    }

    result = MapTypeDecoder.decode(input)
    expected = %{"test_key" => "test_value"}

    assert result == expected
  end
end
