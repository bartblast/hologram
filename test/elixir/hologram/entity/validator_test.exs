defmodule Hologram.Entity.ValidatorTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Entity.Validator

  describe "attr_value_valid?/3" do
    test "validates :boolean values" do
      assert attr_value_valid?(true, :boolean)
      assert attr_value_valid?(false, :boolean)
      refute attr_value_valid?("true", :boolean)
      refute attr_value_valid?(1, :boolean)
    end

    test "validates :date values" do
      assert attr_value_valid?(~D[2026-07-17], :date)
      refute attr_value_valid?("2026-07-17", :date)
      refute attr_value_valid?(~N[2026-07-17 12:00:00], :date)
      refute attr_value_valid?(~U[2026-07-17 12:00:00Z], :date)
    end

    test "validates :datetime values" do
      assert attr_value_valid?(~U[2026-07-17 12:00:00Z], :datetime)
      refute attr_value_valid?(~N[2026-07-17 12:00:00], :datetime)
      refute attr_value_valid?(~D[2026-07-17], :datetime)
      refute attr_value_valid?("2026-07-17T12:00:00Z", :datetime)
    end

    test "accepts :datetime values in any time zone representation" do
      shifted_datetime = %{~U[2026-07-17 12:00:00Z] | time_zone: "Europe/Warsaw"}

      assert attr_value_valid?(shifted_datetime, :datetime)
    end

    test "validates :enum values against the declared value set" do
      assert attr_value_valid?(:done, :enum, values: [:done, :todo])
      refute attr_value_valid?(:cancelled, :enum, values: [:done, :todo])
      refute attr_value_valid?("done", :enum, values: [:done, :todo])
    end

    test "validates :float values" do
      assert attr_value_valid?(1.5, :float)
      assert attr_value_valid?(-0.0, :float)
      refute attr_value_valid?(1, :float)
      refute attr_value_valid?("1.5", :float)
    end

    test "validates :integer values within Postgres int8 bounds" do
      assert attr_value_valid?(5, :integer)
      assert attr_value_valid?(-9_223_372_036_854_775_808, :integer)
      assert attr_value_valid?(9_223_372_036_854_775_807, :integer)
      refute attr_value_valid?(-9_223_372_036_854_775_809, :integer)
      refute attr_value_valid?(9_223_372_036_854_775_808, :integer)
      refute attr_value_valid?(1.0, :integer)
    end

    test "validates :string values" do
      assert attr_value_valid?("abc", :string)
      assert attr_value_valid?("", :string)
      refute attr_value_valid?(<<255>>, :string)
      refute attr_value_valid?(5, :string)
      refute attr_value_valid?(:abc, :string)
    end

    test "accepts nil only when the optional option is true" do
      assert attr_value_valid?(nil, :string, optional: true)
      refute attr_value_valid?(nil, :string)
      refute attr_value_valid?(nil, :string, optional: false)
      assert attr_value_valid?(nil, :enum, optional: true, values: [:done, :todo])
    end
  end
end
