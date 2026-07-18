defmodule Hologram.Database.CodecTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Database.Codec

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

    test "passes :float values through" do
      assert decode(1.5, :float) == 1.5
    end

    test "passes :integer values through" do
      assert decode(9, :integer) == 9
    end

    test "passes :string values through" do
      assert decode("abc", :string) == "abc"
    end

    test "decodes :uuid values from 16-byte binaries to strings" do
      assert decode(@uuid_binary, :uuid) == @uuid_string
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

    test "passes :float values through" do
      assert encode(2.5, :float) == 2.5
    end

    test "passes :integer values through" do
      assert encode(11, :integer) == 11
    end

    test "passes :string values through" do
      assert encode("xyz", :string) == "xyz"
    end

    test "encodes :uuid values from strings to 16-byte binaries" do
      assert encode(@uuid_string, :uuid) == @uuid_binary
    end
  end
end
