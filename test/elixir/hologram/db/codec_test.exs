defmodule Hologram.DB.CodecTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.DB.Codec

  alias Hologram.DB.Connection
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

    test "passes :time values through" do
      assert decode(~T[11:00:00.123456], :time) == ~T[11:00:00.123456]
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

  describe "decode_json/2" do
    test "reads nil back for any type" do
      assert decode_json(nil, :datetime) == {:ok, nil}
    end

    test "reads :boolean values back" do
      assert decode_json(false, :boolean) == {:ok, false}
    end

    test "reads :date values back from their ISO 8601 form" do
      assert decode_json("2026-07-19", :date) == {:ok, ~D[2026-07-19]}
    end

    test "reads :datetime values back from their ISO 8601 form" do
      assert decode_json("2026-07-18T08:30:00.123456Z", :datetime) ==
               {:ok, ~U[2026-07-18 08:30:00.123456Z]}
    end

    test "reads a :datetime value given with an offset back as its UTC representation" do
      assert decode_json("2026-07-18T10:30:00.123456+02:00", :datetime) ==
               {:ok, ~U[2026-07-18 08:30:00.123456Z]}
    end

    test "reads :enum values back from their labels" do
      assert decode_json("high", :enum) == {:ok, :high}
    end

    test "reads :enum values that are modules back from their labels" do
      assert decode_json("Hologram.Test.Fixtures.Role.Module1", :enum) == {:ok, Module1}
    end

    test "reads :float values back" do
      assert decode_json(2.5, :float) == {:ok, 2.5}
    end

    # Compared strictly: an integer equals the float of the same value under ==, so the
    # assertion would hold against a clause that did not convert at all.
    test "reads a whole number back as a :float value" do
      assert decode_json(2, :float) === {:ok, 2.0}
    end

    test "reads :integer values back" do
      assert decode_json(11, :integer) == {:ok, 11}
    end

    test "reads a map back" do
      assert decode_json(%{"title" => 3}, :map) == {:ok, %{"title" => 3}}
    end

    test "reads :string values back" do
      assert decode_json("xyz", :string) == {:ok, "xyz"}
    end

    test "reads :time values back from their ISO 8601 form" do
      assert decode_json("11:00:00", :time) == {:ok, ~T[11:00:00]}
      assert decode_json("11:00:00.123456", :time) == {:ok, ~T[11:00:00.123456]}
    end

    test "reads :uuid values back as they are spelled" do
      assert decode_json(@uuid_string, :uuid) == {:ok, @uuid_string}
    end

    test "reads back every value encode_json/2 writes" do
      values = [
        {false, :boolean},
        {~D[2026-07-19], :date},
        {~U[2026-07-18 08:30:00.123456Z], :datetime},
        {Module1, :enum},
        {2.5, :float},
        {11, :integer},
        {%{"title" => 3}, :map},
        {"xyz", :string},
        {~T[11:00:00.123456], :time},
        {@uuid_string, :uuid}
      ]

      round_tripped =
        Enum.map(values, fn {value, type} ->
          {:ok, decoded} =
            value
            |> encode_json(type)
            |> Jason.encode!()
            |> Jason.decode!()
            |> decode_json(type)

          {decoded, type}
        end)

      assert round_tripped == values
    end

    # The plain inverse, taking the wire at its word - promoting to full precision is encode_json/2's
    # job, and a value read here has already been through it. What has not is a value Postgres
    # itself spelled, which strips a fraction's trailing zeros: those are normalized where they
    # are read, not here.
    test "reads a :time value back at the precision its spelling carries" do
      {:ok, whole_second} = decode_json("11:00:00", :time)
      {:ok, stripped} = decode_json("11:00:00.1", :time)
      {:ok, full} = decode_json("11:00:00.123456", :time)

      assert whole_second.microsecond == {0, 0}
      assert stripped.microsecond == {100_000, 1}
      assert full.microsecond == {123_456, 6}
    end

    # An integer with arbitrary precision cannot always become a 64-bit float, and the promotion
    # raises rather than saturating - so the refusal has to be an answer, not an exception.
    test "refuses an integer too large to be a :float value" do
      too_large =
        "9"
        |> String.duplicate(400)
        |> String.to_integer()

      assert decode_json(too_large, :float) == :error
    end

    test "refuses a value that is not the type's JSON form" do
      assert decode_json("yes", :boolean) == :error
      assert decode_json("2026-13-40", :date) == :error
      assert decode_json("not a datetime", :datetime) == :error
      assert decode_json("no_such_label_for_codec_test", :enum) == :error
      assert decode_json("No.Such.Module.For.Codec.Test", :enum) == :error
      assert decode_json("2.5", :float) == :error
      assert decode_json("1", :integer) == :error
      assert decode_json([], :map) == :error
      assert decode_json(1, :string) == :error
      assert decode_json("25:00:00", :time) == :error
      assert decode_json(1, :uuid) == :error
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

    test "promotes :time values to microsecond precision" do
      assert encode(~T[11:00:00], :time) == ~T[11:00:00.000000]
      assert encode(~T[11:00:00.1], :time) == ~T[11:00:00.100000]
      assert encode(~T[11:00:00.123456], :time) == ~T[11:00:00.123456]
    end

    test "encodes :uuid values from strings to 16-byte binaries" do
      assert encode(@uuid_string, :uuid) == @uuid_binary
    end
  end

  # The :time pass-through clauses of encode/2 and decode/2 rest on the driver speaking %Time{}
  # for a time column, which is a claim about Postgrex rather than about this module - so it is
  # checked against a real one. The parameter goes out at the precision the struct holds and the
  # column keeps it, time being microseconds since midnight at every precision.
  describe "encode/2 and decode/2 against the driver" do
    test "round-trips a :time value through a time column" do
      encoded = encode(~T[11:00:00.123456], :time)

      {:ok, %Postgrex.Result{rows: [[raw]]}} = Connection.query("SELECT $1::time", [encoded])

      assert decode(raw, :time) == ~T[11:00:00.123456]
    end

    # This is why encode/2 promotes: the column keeps no record of how few digits a value was
    # written with, so a whole second put in as {0, 0} comes back as {0, 6} and would spell
    # itself two ways depending on which side of the write it was read from.
    test "reads a whole-second :time value back at microsecond precision" do
      encoded = encode(~T[11:00:00], :time)

      {:ok, %Postgrex.Result{rows: [[raw]]}} = Connection.query("SELECT $1::time", [encoded])

      assert decode(raw, :time) == ~T[11:00:00.000000]
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

    # One time of day is one wire spelling, always six fractional digits - the client compares
    # temporal values as the plain strings they are, so a value written with fewer digits and
    # left that way would be a second spelling of a time the server already has.
    test "encodes :time values as ISO 8601 strings at full precision" do
      assert encode_json(~T[11:00:00], :time) == "11:00:00.000000"
      assert encode_json(~T[11:00:00.1], :time) == "11:00:00.100000"
      assert encode_json(~T[11:00:00.123456], :time) == "11:00:00.123456"
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
        {~T[11:00:00.123456], :time},
        {@uuid_string, :uuid}
      ]

      encoded = Enum.map(values, fn {value, type} -> encode_json(value, type) end)

      assert Jason.encode!(encoded) ==
               ~s([false,"2026-07-19","2026-07-18T08:30:00.123456Z","Hologram.Test.Fixtures.Role.Module1",2.5,11,{"title":3},"xyz","11:00:00.123456","#{@uuid_string}"])
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
