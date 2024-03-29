defmodule Hologram.Compiler.DecoderTest do
  use Hologram.Test.UnitCase, async: true
  alias Hologram.Compiler.Decoder

  test "atom" do
    input = %{"type" => "atom", "value" => "test"}
    result = Decoder.decode(input)
    assert result === :test
  end

  test "boolean" do
    input = %{"type" => "boolean", "value" => true}
    result = Decoder.decode(input)
    assert result === true
  end

  test "float" do
    input = %{"type" => "float", "value" => 1.23}
    result = Decoder.decode(input)
    assert result === 1.23
  end

  test "integer" do
    input = %{"type" => "integer", "value" => 1}
    result = Decoder.decode(input)
    assert result === 1
  end

  test "list" do
    input = %{
      "type" => "list",
      "data" => [
        %{"type" => "integer", "value" => 1},
        %{"type" => "integer", "value" => 2}
      ]
    }

    result = Decoder.decode(input)
    assert is_list(result)
  end

  test "map" do
    input = %{
      "type" => "map",
      "data" => %{
        "~string[test_key]" => %{
          "type" => "string",
          "value" => "test_value"
        }
      }
    }

    result = Decoder.decode(input)
    assert is_map(result)
  end

  test "module" do
    input = %{"type" => "module", "className" => "Elixir_Hologram_Compiler_DecoderTest"}
    result = Decoder.decode(input)
    assert is_atom(result)
  end

  test "string" do
    input = %{"type" => "string", "value" => "test"}
    result = Decoder.decode(input)
    assert result === "test"
  end

  test "tuple" do
    input = %{
      "type" => "tuple",
      "data" => [
        %{"type" => "integer", "value" => 1},
        %{"type" => "integer", "value" => 2}
      ]
    }

    result = Decoder.decode(input)
    assert is_tuple(result)
  end

  test "nested" do
    input = %{
      "type" => "list",
      "data" => [
        %{"type" => "integer", "value" => 1},
        %{
          "type" => "tuple",
          "data" => [
            %{"type" => "integer", "value" => 2},
            %{"type" => "integer", "value" => 3}
          ]
        }
      ]
    }

    result = Decoder.decode(input)
    expected = [1, {2, 3}]

    assert result == expected
  end
end
