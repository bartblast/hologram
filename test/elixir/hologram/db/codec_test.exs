defmodule Hologram.DB.CodecTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.DB.Codec

  alias Hologram.Test.Fixtures.Role.Module1

  @uuid_binary Base.decode16!("0192b1e97a2b7c3d8e4f5a6b7c8d9e0f", case: :lower)
  @uuid_string "0192b1e9-7a2b-7c3d-8e4f-5a6b7c8d9e0f"

  describe "decode/2" do
    test "passes nil through for any type" do
      assert decode(nil, :string) == nil
    end

    test "passes :boolean values through" do
      assert decode(true, :boolean) == true
    end

    test "passes :date values through" do
      assert decode(~D[2026-07-18], :date) == ~D[2026-07-18]
    end

    test "passes :datetime values through" do
      assert decode(~U[2026-07-18 08:30:00.123456Z], :datetime) == ~U[2026-07-18 08:30:00.123456Z]
    end

    test "decodes :enum values to existing atoms" do
      assert decode("high", :enum) == :high
    end

    test "decodes :enum labels beginning with an uppercase letter to modules" do
      assert decode("Hologram.Test.Fixtures.Role.Module1", :enum) == Module1
    end

    test "passes :float values through" do
      assert decode(1.5, :float) == 1.5
    end

    test "passes :integer values through" do
      assert decode(9, :integer) == 9
    end

    test "passes a map through unchanged" do
      assert decode(%{"title" => 3}, :map) == %{"title" => 3}
    end

    test "passes :string values through" do
      assert decode("abc", :string) == "abc"
    end

    test "decodes :uuid values from 16-byte binaries to strings" do
      assert decode(@uuid_binary, :uuid) == @uuid_string
    end
  end

  describe "decode_enum_label/1" do
    test "returns the module named by a label beginning with an uppercase letter" do
      assert decode_enum_label("Hologram.Test.Fixtures.Role.Module1") == Module1
    end

    test "returns the plain atom named by any other label" do
      assert decode_enum_label("high") == :high
    end
  end

  describe "encode/2" do
    test "passes nil through for any type" do
      assert encode(nil, :string) == nil
    end

    test "passes :boolean values through" do
      assert encode(false, :boolean) == false
    end

    test "passes :date values through" do
      assert encode(~D[2026-07-19], :date) == ~D[2026-07-19]
    end

    test "keeps UTC :datetime values" do
      assert encode(~U[2026-07-18 08:30:00.123456Z], :datetime) == ~U[2026-07-18 08:30:00.123456Z]
    end

    test "normalizes non-UTC :datetime values to their UTC representation" do
      warsaw_datetime = %DateTime{
        year: 2026,
        month: 7,
        day: 18,
        hour: 10,
        minute: 30,
        second: 0,
        microsecond: {123_456, 6},
        calendar: Calendar.ISO,
        time_zone: "Europe/Warsaw",
        zone_abbr: "CEST",
        utc_offset: 3_600,
        std_offset: 3_600
      }

      assert encode(warsaw_datetime, :datetime) == ~U[2026-07-18 08:30:00.123456Z]
    end

    test "encodes :enum values to strings" do
      assert encode(:low, :enum) == "low"
    end

    test "encodes :enum values that are modules without their Elixir prefix" do
      assert encode(Module1, :enum) == "Hologram.Test.Fixtures.Role.Module1"
    end

    test "passes :float values through" do
      assert encode(2.5, :float) == 2.5
    end

    test "passes :integer values through" do
      assert encode(11, :integer) == 11
    end

    test "passes a map through unchanged" do
      assert encode(%{"title" => 3}, :map) == %{"title" => 3}
    end

    test "passes :string values through" do
      assert encode("xyz", :string) == "xyz"
    end

    test "encodes :uuid values from strings to 16-byte binaries" do
      assert encode(@uuid_string, :uuid) == @uuid_binary
    end
  end

  describe "encode_json/2" do
    test "passes nil through for any type" do
      assert encode_json(nil, :datetime) == nil
    end

    test "passes :boolean values through" do
      assert encode_json(false, :boolean) == false
    end

    test "encodes :date values as ISO 8601 strings" do
      assert encode_json(~D[2026-07-19], :date) == "2026-07-19"
    end

    test "encodes :datetime values as ISO 8601 strings" do
      assert encode_json(~U[2026-07-18 08:30:00.123456Z], :datetime) ==
               "2026-07-18T08:30:00.123456Z"
    end

    test "normalizes non-UTC :datetime values to their UTC representation" do
      warsaw_datetime = %DateTime{
        year: 2026,
        month: 7,
        day: 18,
        hour: 10,
        minute: 30,
        second: 0,
        microsecond: {123_456, 6},
        calendar: Calendar.ISO,
        time_zone: "Europe/Warsaw",
        zone_abbr: "CEST",
        utc_offset: 3_600,
        std_offset: 3_600
      }

      assert encode_json(warsaw_datetime, :datetime) == "2026-07-18T08:30:00.123456Z"
    end

    test "encodes :enum values to their labels" do
      assert encode_json(:low, :enum) == "low"
    end

    test "encodes :enum values that are modules without their Elixir prefix" do
      assert encode_json(Module1, :enum) == "Hologram.Test.Fixtures.Role.Module1"
    end

    test "passes :float values through" do
      assert encode_json(2.5, :float) == 2.5
    end

    test "passes :integer values through" do
      assert encode_json(11, :integer) == 11
    end

    test "passes a map through unchanged" do
      assert encode_json(%{"title" => 3}, :map) == %{"title" => 3}
    end

    test "passes :string values through" do
      assert encode_json("xyz", :string) == "xyz"
    end

    test "keeps :uuid values as canonical strings" do
      assert encode_json(@uuid_string, :uuid) == @uuid_string
    end

    test "encodes every admitted type into a term Jason accepts" do
      values = [
        {false, :boolean},
        {~D[2026-07-19], :date},
        {~U[2026-07-18 08:30:00.123456Z], :datetime},
        {Module1, :enum},
        {2.5, :float},
        {11, :integer},
        {%{"title" => 3}, :map},
        {"xyz", :string},
        {@uuid_string, :uuid}
      ]

      encoded = Enum.map(values, fn {value, type} -> encode_json(value, type) end)

      assert Jason.encode!(encoded) ==
               ~s([false,"2026-07-19","2026-07-18T08:30:00.123456Z","Hologram.Test.Fixtures.Role.Module1",2.5,11,{"title":3},"xyz","#{@uuid_string}"])
    end
  end

  describe "encode_enum_value/1" do
    test "strips the Elixir prefix of a module" do
      assert encode_enum_value(Module1) == "Hologram.Test.Fixtures.Role.Module1"
    end

    test "keeps a plain atom as it is spelled" do
      assert encode_enum_value(:high) == "high"
    end
  end
end
