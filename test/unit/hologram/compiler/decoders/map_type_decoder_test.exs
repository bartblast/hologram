defmodule Hologram.Compiler.MapTypeDecoderTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Compiler.MapTypeDecoder

  test "encoded map decoding" do
    value = %{
      "type" => "map",
      "data" => %{
        "~string[test_key]" => %{
          "type" => "string",
          "value" => "test_value"
        }
      }
    }

    result = MapTypeDecoder.decode(value)
    expected = %{"test_key" => "test_value"}

    assert result == expected
  end

  test "encoded atom key decoding" do
    value = %{
      "data" => %{
        "~atom[test_key]" => %{
          "type" => "string",
          "value" => "test_value"
        }
      }
    }

    result = MapTypeDecoder.decode(value)
    expected = %{test_key: "test_value"}

    assert result == expected
  end

  test "encoded string key decoding" do
    value = %{
      "data" => %{
        "~string[test_key]" => %{
          "type" => "string",
          "value" => "test_value"
        }
      }
    }

    result = MapTypeDecoder.decode(value)
    expected = %{"test_key" => "test_value"}

    assert result == expected
  end
end
