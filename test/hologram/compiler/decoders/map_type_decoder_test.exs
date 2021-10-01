defmodule Hologram.Compiler.MapTypeDecoderTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Compiler.MapTypeDecoder

  test "decode/1" do
    data = %{
      "~string[test_key]" => %{
        "type" => "string",
        "value" => "test_value"
      }
    }

    result = MapTypeDecoder.decode(data)
    expected = %{"test_key" => "test_value"}

    assert result == expected
  end

  test "atom key" do
    data = %{
      "~atom[test_key]" => %{
        "type" => "string",
        "value" => "test_value"
      }
    }

    result = MapTypeDecoder.decode(data)
    expected = %{test_key: "test_value"}

    assert result == expected
  end

  test "string key" do
    data = %{
      "~string[test_key]" => %{
        "type" => "string",
        "value" => "test_value"
      }
    }

    result = MapTypeDecoder.decode(data)
    expected = %{"test_key" => "test_value"}

    assert result == expected
  end
end
