defmodule Hologram.Compiler.MapTypeDecoderTest do
  use Hologram.TestCase, async: true
  alias Hologram.Compiler.MapTypeDecoder

  test "empty map" do
    input = %{}
    result = MapTypeDecoder.decode(input)

    assert result == %{}
  end

  test "non-empty, not-nested map" do
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

  test "nested map" do
    input =
      %{
        "~string[test_key_1]" => %{
          "type" => "map",
          "data" => %{
            "~string[test_key_2]" => %{
              "type" => "string",
              "value" => "test_value"
            }
          }
        }
      }

    result = MapTypeDecoder.decode(input)

    expected =
      %{
        "test_key_1" => %{
          "test_key_2" => "test_value"
        }
      }

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
