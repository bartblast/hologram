defmodule Hologram.Entity.ValidatorTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Entity.Validator

  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module10
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module4

  describe "attribute_value_valid?/3" do
    test "validates :boolean values" do
      assert attribute_value_valid?(true, :boolean)
      assert attribute_value_valid?(false, :boolean)
      refute attribute_value_valid?("true", :boolean)
      refute attribute_value_valid?(1, :boolean)
    end

    test "validates :date values" do
      assert attribute_value_valid?(~D[2026-07-17], :date)
      refute attribute_value_valid?("2026-07-17", :date)
      refute attribute_value_valid?(~N[2026-07-17 12:00:00], :date)
      refute attribute_value_valid?(~U[2026-07-17 12:00:00Z], :date)
    end

    test "validates :datetime values" do
      assert attribute_value_valid?(~U[2026-07-17 12:00:00Z], :datetime)
      refute attribute_value_valid?(~N[2026-07-17 12:00:00], :datetime)
      refute attribute_value_valid?(~D[2026-07-17], :datetime)
      refute attribute_value_valid?("2026-07-17T12:00:00Z", :datetime)
    end

    test "accepts :datetime values in any time zone representation" do
      shifted_datetime = %{~U[2026-07-17 12:00:00Z] | time_zone: "Europe/Warsaw"}

      assert attribute_value_valid?(shifted_datetime, :datetime)
    end

    test "validates :enum values against the declared value set" do
      assert attribute_value_valid?(:done, :enum, values: [:done, :todo])
      refute attribute_value_valid?(:cancelled, :enum, values: [:done, :todo])
      refute attribute_value_valid?("done", :enum, values: [:done, :todo])
    end

    test "validates :float values" do
      assert attribute_value_valid?(1.5, :float)
      assert attribute_value_valid?(-0.0, :float)
      refute attribute_value_valid?(1, :float)
      refute attribute_value_valid?("1.5", :float)
    end

    test "validates :integer values within Postgres int8 bounds" do
      assert attribute_value_valid?(5, :integer)
      assert attribute_value_valid?(-9_223_372_036_854_775_808, :integer)
      assert attribute_value_valid?(9_223_372_036_854_775_807, :integer)
      refute attribute_value_valid?(-9_223_372_036_854_775_809, :integer)
      refute attribute_value_valid?(9_223_372_036_854_775_808, :integer)
      refute attribute_value_valid?(1.0, :integer)
    end

    test "validates :string values" do
      assert attribute_value_valid?("abc", :string)
      assert attribute_value_valid?("", :string)
      refute attribute_value_valid?(<<255>>, :string)
      refute attribute_value_valid?(5, :string)
      refute attribute_value_valid?(:abc, :string)
    end

    test "validates :uuid values" do
      assert attribute_value_valid?("018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f", :uuid)
      refute attribute_value_valid?("018f4571a1b27c3d8e4f5a6b7c8d9e0f", :uuid)
      refute attribute_value_valid?("018f45-71a1b2-7c3d-8e4f-5a6b7c8d9e0f", :uuid)
      refute attribute_value_valid?("018F4571-A1B2-7C3D-8E4F-5A6B7C8D9E0F", :uuid)
      refute attribute_value_valid?("018f4571-a1b2-7c3d-8e4f", :uuid)
      refute attribute_value_valid?("not-a-uuid", :uuid)
      refute attribute_value_valid?(5, :uuid)
    end

    test "accepts nil only when the optional option is true" do
      assert attribute_value_valid?(nil, :string, optional: true)
      refute attribute_value_valid?(nil, :string)
      refute attribute_value_valid?(nil, :string, optional: false)
      assert attribute_value_valid?(nil, :enum, optional: true, values: [:done, :todo])
    end
  end

  describe "error_message/3" do
    test "builds one line per violation naming attribute, expectation, and received value" do
      data = %{count: 0, priority: 9}
      {:error, errors} = validate(Module10, data)

      expected = """
      invalid data for Hologram.Test.Fixtures.Entity.Module10:
        * attribute :count must be at least 1, got: 0
        * attribute :priority must be in 1..5, got: 9\
      """

      assert error_message(Module10, data, errors) == expected
    end

    test "describes required and unknown violations without received values" do
      data = %{b: 1, e: 2}
      {:error, errors} = validate(Module2, data)

      expected = """
      invalid data for Hologram.Test.Fixtures.Entity.Module2:
        * attribute :a is required
        * attribute :c is required
        * :e is not a declared attribute or to-one reference\
      """

      assert error_message(Module2, data, errors) == expected
    end

    test "describes reference violations with reference wording" do
      required_data = %{}
      {:error, required_errors} = validate(Module3, required_data)

      expected_required = """
      invalid data for Hologram.Test.Fixtures.Entity.Module3:
        * reference :c_id is required\
      """

      assert error_message(Module3, required_data, required_errors) == expected_required

      invalid_data = %{c_id: "garbage"}
      {:error, invalid_errors} = validate(Module3, invalid_data)

      expected_invalid = """
      invalid data for Hologram.Test.Fixtures.Entity.Module3:
        * reference :c_id must be a valid entity id, got: "garbage"\
      """

      assert error_message(Module3, invalid_data, invalid_errors) == expected_invalid
    end

    test "describes each constraint violation kind" do
      data = %{
        bio: "01234567890",
        country_code: "USA",
        email: "nope",
        held_at: ~U[2027-01-01 00:00:00Z],
        rating: "high",
        status: "x",
        username: "ab"
      }

      errors = [
        {:bio, {:max_length, 10}},
        {:country_code, {:length, 2}},
        {:email, {:format, ~r/@/}},
        {:held_at, {:max, ~U[2026-12-31 23:59:59Z]}},
        {:rating, {:type, :float}},
        {:status, {:values, [:draft, :published]}},
        {:username, {:min_length, 3}}
      ]

      expected = """
      invalid data for Hologram.Test.Fixtures.Entity.Module10:
        * attribute :bio must be at most 10 characters, got: "01234567890"
        * attribute :country_code must be exactly 2 characters, got: "USA"
        * attribute :email must match ~r/@/, got: "nope"
        * attribute :held_at must be at most ~U[2026-12-31 23:59:59Z], got: ~U[2027-01-01 00:00:00Z]
        * attribute :rating must be of type :float, got: "high"
        * attribute :status must be one of [:draft, :published], got: "x"
        * attribute :username must be at least 3 characters, got: "ab"\
      """

      assert error_message(Module10, data, errors) == expected
    end
  end

  describe "validate/2" do
    test "returns :ok for complete valid data" do
      assert validate(Module2, %{a: true, b: 1, c: "x"}) == :ok
    end

    test "returns :ok when optional attributes are absent" do
      assert validate(Module2, %{a: false, c: "x"}) == :ok
    end

    test "returns :ok for entity type with no declared attributes and empty data" do
      assert validate(Module1, %{}) == :ok
    end

    test "passes declaration options through to value validation" do
      data = %{a: ~D[2026-07-17], b: ~U[2026-07-17 12:00:00Z], c: :x, d: 1.5}

      assert validate(Module4, data) == :ok
    end

    test "reports required violations for absent non-optional attributes regardless of declared defaults" do
      assert validate(Module2, %{b: 1}) == {:error, [{:a, :required}, {:c, :required}]}
    end

    test "reports required violation for nil non-optional attribute" do
      assert validate(Module2, %{a: true, b: nil, c: nil}) == {:error, [{:c, :required}]}
    end

    test "reports type violations with the expected type" do
      assert validate(Module2, %{a: 5, c: "x"}) == {:error, [{:a, {:type, :boolean}}]}
    end

    test "reports values violations for enum attributes" do
      data = %{a: ~D[2026-07-17], b: ~U[2026-07-17 12:00:00Z], d: 1.5}

      assert validate(Module4, Map.put(data, :c, :z)) == {:error, [{:c, {:values, [:x, :y]}}]}
      assert validate(Module4, Map.put(data, :c, "x")) == {:error, [{:c, {:values, [:x, :y]}}]}
    end

    test "returns :ok for values on the declared bounds" do
      data = %{
        bio: "0123456789",
        count: 1,
        country_code: "us",
        held_at: ~U[2026-01-01 00:00:00Z],
        priority: 1,
        rating: 0.0,
        released_on: ~D[2030-12-31],
        username: "abc"
      }

      assert validate(Module10, data) == :ok
    end

    test "reports min violations with the declared minimum" do
      assert validate(Module10, %{count: 0}) == {:error, [{:count, {:min, 1}}]}

      assert validate(Module10, %{count: 5, held_at: ~U[2025-12-31 23:59:59Z]}) ==
               {:error, [{:held_at, {:min, ~U[2026-01-01 00:00:00Z]}}]}

      assert validate(Module10, %{count: 5, rating: -0.5}) == {:error, [{:rating, {:min, 0}}]}
    end

    test "reports max violations with the declared maximum" do
      assert validate(Module10, %{count: 11}) == {:error, [{:count, {:max, 10}}]}

      assert validate(Module10, %{count: 5, rating: 5.5}) == {:error, [{:rating, {:max, 5.0}}]}

      assert validate(Module10, %{count: 5, released_on: ~D[2031-01-01]}) ==
               {:error, [{:released_on, {:max, ~D[2030-12-31]}}]}
    end

    test "reports in violations with the declared range" do
      assert validate(Module10, %{count: 5, priority: 0}) ==
               {:error, [{:priority, {:in, 1..5}}]}

      assert validate(Module10, %{count: 5, priority: 6}) ==
               {:error, [{:priority, {:in, 1..5}}]}
    end

    test "honors the step of a stepped in range" do
      assert validate(Module10, %{count: 5, percent: 15}) == :ok

      assert validate(Module10, %{count: 5, percent: 3}) ==
               {:error, [{:percent, {:in, 0..100//5}}]}
    end

    test "reports length violations with the declared exact length" do
      assert validate(Module10, %{count: 5, country_code: "USA"}) ==
               {:error, [{:country_code, {:length, 2}}]}

      assert validate(Module10, %{count: 5, country_code: "U"}) ==
               {:error, [{:country_code, {:length, 2}}]}
    end

    test "reports min_length violations with the declared minimum" do
      assert validate(Module10, %{count: 5, username: "ab"}) ==
               {:error, [{:username, {:min_length, 3}}]}
    end

    test "reports max_length violations with the declared maximum" do
      assert validate(Module10, %{count: 5, bio: "01234567890"}) ==
               {:error, [{:bio, {:max_length, 10}}]}
    end

    test "counts string lengths in code points" do
      # e + combining acute accent: 1 grapheme, 2 code points, 3 bytes
      assert validate(Module10, %{count: 5, country_code: "e\u0301"}) == :ok

      # precomposed e with acute: 1 grapheme, 1 code point, 2 bytes
      assert validate(Module10, %{count: 5, country_code: "\u00E9"}) ==
               {:error, [{:country_code, {:length, 2}}]}
    end

    test "reports format violations with the declared pattern" do
      assert validate(Module10, %{count: 5, email: "a@b.com"}) == :ok

      assert {:error, [{:email, {:format, format}}]} =
               validate(Module10, %{count: 5, email: "nope"})

      assert Regex.source(format) == "@"
    end

    test "accumulates multiple constraint violations per attribute" do
      assert {:error, [{:handle, {:format, format}}, {:handle, {:min_length, 3}}]} =
               validate(Module10, %{count: 5, handle: "A?"})

      assert Regex.source(format) == "^[a-z_]+$"
    end

    test "type violation suppresses constraint checks" do
      assert validate(Module10, %{count: "5"}) == {:error, [{:count, {:type, :integer}}]}
    end

    test "validates reference fields" do
      target_id = "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f"

      assert validate(Module3, %{c_id: target_id}) == :ok
      assert validate(Module3, %{b_id: nil, c_id: target_id}) == :ok
      assert validate(Module3, %{}) == {:error, [{:c_id, :required}]}
      assert validate(Module3, %{c_id: nil}) == {:error, [{:c_id, :required}]}
      assert validate(Module3, %{c_id: "garbage"}) == {:error, [{:c_id, {:type, :uuid}}]}
    end

    test "reports to-many relationship names as unknown" do
      target_id = "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f"

      assert validate(Module3, %{a: [target_id], c_id: target_id}) ==
               {:error, [{:a, :unknown}]}
    end

    test "reports unknown keys" do
      assert validate(Module2, %{a: true, c: "x", e: 1}) == {:error, [{:e, :unknown}]}
    end

    test "accumulates all errors sorted by name" do
      assert validate(Module2, %{b: "nope", e: 1}) ==
               {:error,
                [{:a, :required}, {:b, {:type, :integer}}, {:c, :required}, {:e, :unknown}]}
    end
  end

  describe "validate_attribute!/4" do
    test "rejects values option on non-enum attribute" do
      expected_msg =
        "values option not allowed for attribute :title in Hologram.Entity.ValidatorTest.InlineEntityFixture8 - the values option applies only to enum attributes"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture8 do
          use Hologram.Entity

          attribute :title, :string, values: [:a, :b]
        end
      end
    end

    test "rejects unknown attribute option" do
      expected_msg =
        "unknown option :require for attribute :title in Hologram.Entity.ValidatorTest.InlineEntityFixture10 - valid attribute options are: :default, :format, :in, :length, :max, :max_length, :min, :min_length, :optional, :values"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture10 do
          use Hologram.Entity

          attribute :title, :string, require: true
        end
      end
    end

    test "rejects unknown attribute type" do
      expected_msg =
        "invalid type :text for attribute :title in Hologram.Entity.ValidatorTest.InlineEntityFixture1 - valid attribute types are: :boolean, :date, :datetime, :enum, :float, :integer, :string"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture1 do
          use Hologram.Entity

          attribute :title, :text
        end
      end
    end

    test "rejects module used as attribute type" do
      expected_msg =
        "invalid type DateTime for attribute :happened_at in Hologram.Entity.ValidatorTest.InlineEntityFixture2 - valid attribute types are: :boolean, :date, :datetime, :enum, :float, :integer, :string"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture2 do
          use Hologram.Entity

          attribute :happened_at, DateTime
        end
      end
    end

    test "rejects default not matching attribute type" do
      expected_msg =
        "invalid default value 5 for attribute :title in Hologram.Entity.ValidatorTest.InlineEntityFixture13 - the default value must match the attribute type :string"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture13 do
          use Hologram.Entity

          attribute :title, :string, default: 5
        end
      end
    end

    test "accepts nil default for optional attribute" do
      defmodule InlineEntityFixture18 do
        use Hologram.Entity

        attribute :status, :enum, values: [:a, :b], default: nil, optional: true
        attribute :title, :string, default: nil, optional: true
      end

      assert InlineEntityFixture18.__attributes__() == [
               {:status, :enum, [values: [:a, :b], default: nil, optional: true]},
               {:title, :string, [default: nil, optional: true]}
             ]
    end

    test "rejects nil default for non-optional attribute" do
      expected_msg =
        "invalid default value nil for enum attribute :status in Hologram.Entity.ValidatorTest.InlineEntityFixture19 - the default value must be one of the declared values or nil when the attribute is optional"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture19 do
          use Hologram.Entity

          attribute :status, :enum, values: [:a, :b], default: nil
        end
      end
    end

    test "rejects default violating type value constraints" do
      expected_msg =
        "invalid default value 9223372036854775808 for attribute :count in Hologram.Entity.ValidatorTest.InlineEntityFixture17 - the default value must match the attribute type :integer"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture17 do
          use Hologram.Entity

          attribute :count, :integer, default: 9_223_372_036_854_775_808
        end
      end
    end

    test "accepts min and max options on bounded attribute types" do
      defmodule InlineEntityFixture28 do
        use Hologram.Entity

        attribute :count, :integer, min: 1, max: 10
        attribute :held_at, :datetime, min: ~U[2026-01-01 00:00:00Z]
        attribute :rating, :float, min: 0, max: 5.0
        attribute :released_on, :date, max: ~D[2030-12-31]
      end

      assert InlineEntityFixture28.__attributes__() == [
               {:count, :integer, [min: 1, max: 10]},
               {:held_at, :datetime, [min: ~U[2026-01-01 00:00:00Z]]},
               {:rating, :float, [min: 0, max: 5.0]},
               {:released_on, :date, [max: ~D[2030-12-31]]}
             ]
    end

    test "accepts equal min and max options" do
      defmodule InlineEntityFixture29 do
        use Hologram.Entity

        attribute :count, :integer, min: 5, max: 5
      end

      assert InlineEntityFixture29.__attributes__() == [{:count, :integer, [min: 5, max: 5]}]
    end

    test "rejects min option on unbounded attribute type" do
      expected_msg =
        "min option not allowed for attribute :title in Hologram.Entity.ValidatorTest.InlineEntityFixture30 - min and max options apply only to integer, float, date and datetime attributes"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture30 do
          use Hologram.Entity

          attribute :title, :string, min: 1
        end
      end
    end

    test "rejects max option on unbounded attribute type" do
      expected_msg =
        "max option not allowed for attribute :archived in Hologram.Entity.ValidatorTest.InlineEntityFixture31 - min and max options apply only to integer, float, date and datetime attributes"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture31 do
          use Hologram.Entity

          attribute :archived, :boolean, max: true
        end
      end
    end

    test "rejects min option not matching attribute type" do
      expected_msg =
        "invalid min option 1.5 for attribute :count in Hologram.Entity.ValidatorTest.InlineEntityFixture32 - the min option must match the attribute type :integer"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture32 do
          use Hologram.Entity

          attribute :count, :integer, min: 1.5
        end
      end
    end

    test "rejects max option not matching attribute type" do
      expected_msg =
        "invalid max option \"2030-12-31\" for attribute :released_on in Hologram.Entity.ValidatorTest.InlineEntityFixture33 - the max option must match the attribute type :date"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture33 do
          use Hologram.Entity

          attribute :released_on, :date, max: "2030-12-31"
        end
      end
    end

    test "rejects non-number min option on float attribute" do
      expected_msg =
        "invalid min option \"0\" for attribute :rating in Hologram.Entity.ValidatorTest.InlineEntityFixture34 - the min option must be a number"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture34 do
          use Hologram.Entity

          attribute :rating, :float, min: "0"
        end
      end
    end

    test "rejects min option beyond integer type bounds" do
      expected_msg =
        "invalid min option 9223372036854775808 for attribute :count in Hologram.Entity.ValidatorTest.InlineEntityFixture35 - the min option must match the attribute type :integer"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture35 do
          use Hologram.Entity

          attribute :count, :integer, min: 9_223_372_036_854_775_808
        end
      end
    end

    test "rejects min greater than max" do
      expected_msg =
        "conflicting min and max options for attribute :count in Hologram.Entity.ValidatorTest.InlineEntityFixture36 - min 10 must be less than or equal to max 1"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture36 do
          use Hologram.Entity

          attribute :count, :integer, min: 10, max: 1
        end
      end
    end

    test "rejects min greater than max on temporal attribute" do
      expected_msg =
        "conflicting min and max options for attribute :released_on in Hologram.Entity.ValidatorTest.InlineEntityFixture37 - min ~D[2030-01-01] must be less than or equal to max ~D[2020-01-01]"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture37 do
          use Hologram.Entity

          attribute :released_on, :date, min: ~D[2030-01-01], max: ~D[2020-01-01]
        end
      end
    end

    test "accepts in option with integer range" do
      defmodule InlineEntityFixture38 do
        use Hologram.Entity

        attribute :percent, :integer, in: 0..100//5
        attribute :priority, :integer, in: 1..5
      end

      assert InlineEntityFixture38.__attributes__() == [
               {:percent, :integer, [in: 0..100//5]},
               {:priority, :integer, [in: 1..5]}
             ]
    end

    test "rejects in option on non-integer attribute type" do
      expected_msg =
        "in option not allowed for attribute :rating in Hologram.Entity.ValidatorTest.InlineEntityFixture39 - the in option applies only to integer attributes"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture39 do
          use Hologram.Entity

          attribute :rating, :float, in: 1..5
        end
      end
    end

    test "rejects non-range in option" do
      expected_msg =
        "invalid in option [1, 2, 3] for attribute :priority in Hologram.Entity.ValidatorTest.InlineEntityFixture40 - the in option must be an integer Range"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture40 do
          use Hologram.Entity

          attribute :priority, :integer, in: [1, 2, 3]
        end
      end
    end

    test "rejects in option range with endpoints beyond integer type bounds" do
      expected_msg =
        "invalid in option 1..9223372036854775808 for attribute :count in Hologram.Entity.ValidatorTest.InlineEntityFixture41 - the in option range endpoints must be valid integer attribute values"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture41 do
          use Hologram.Entity

          attribute :count, :integer, in: 1..9_223_372_036_854_775_808
        end
      end
    end

    test "rejects empty in option range" do
      expected_msg =
        "invalid in option 1..0//1 for attribute :count in Hologram.Entity.ValidatorTest.InlineEntityFixture42 - the in option range must not be empty"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture42 do
          use Hologram.Entity

          attribute :count, :integer, in: 1..0//1
        end
      end
    end

    test "rejects in option combined with min and max options" do
      expected_msg =
        "conflicting options for attribute :count in Hologram.Entity.ValidatorTest.InlineEntityFixture43 - the in option can't be combined with the min and max options"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture43 do
          use Hologram.Entity

          attribute :count, :integer, in: 1..10, min: 1
        end
      end
    end

    test "accepts length options on string attributes" do
      defmodule InlineEntityFixture44 do
        use Hologram.Entity

        attribute :bio, :string, max_length: 500
        attribute :country_code, :string, length: 2
        attribute :username, :string, min_length: 3, max_length: 32
      end

      assert InlineEntityFixture44.__attributes__() == [
               {:bio, :string, [max_length: 500]},
               {:country_code, :string, [length: 2]},
               {:username, :string, [min_length: 3, max_length: 32]}
             ]
    end

    test "rejects length option on non-string attribute type" do
      expected_msg =
        "length option not allowed for attribute :count in Hologram.Entity.ValidatorTest.InlineEntityFixture45 - length options apply only to string attributes"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture45 do
          use Hologram.Entity

          attribute :count, :integer, length: 2
        end
      end
    end

    test "rejects max_length option on non-string attribute type" do
      expected_msg =
        "max_length option not allowed for attribute :held_at in Hologram.Entity.ValidatorTest.InlineEntityFixture46 - length options apply only to string attributes"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture46 do
          use Hologram.Entity

          attribute :held_at, :datetime, max_length: 10
        end
      end
    end

    test "rejects non-integer length option" do
      expected_msg =
        "invalid length option \"2\" for attribute :country_code in Hologram.Entity.ValidatorTest.InlineEntityFixture47 - the length option must be a non-negative integer"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture47 do
          use Hologram.Entity

          attribute :country_code, :string, length: "2"
        end
      end
    end

    test "rejects negative min_length option" do
      expected_msg =
        "invalid min_length option -1 for attribute :username in Hologram.Entity.ValidatorTest.InlineEntityFixture48 - the min_length option must be a non-negative integer"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture48 do
          use Hologram.Entity

          attribute :username, :string, min_length: -1
        end
      end
    end

    test "rejects length option combined with min_length and max_length options" do
      expected_msg =
        "conflicting options for attribute :username in Hologram.Entity.ValidatorTest.InlineEntityFixture49 - the length option can't be combined with the min_length and max_length options"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture49 do
          use Hologram.Entity

          attribute :username, :string, length: 2, max_length: 5
        end
      end
    end

    test "rejects min_length greater than max_length" do
      expected_msg =
        "conflicting min_length and max_length options for attribute :username in Hologram.Entity.ValidatorTest.InlineEntityFixture50 - min_length 10 must be less than or equal to max_length 1"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture50 do
          use Hologram.Entity

          attribute :username, :string, min_length: 10, max_length: 1
        end
      end
    end

    test "accepts format option on string attribute" do
      defmodule InlineEntityFixture51 do
        use Hologram.Entity

        attribute :email, :string, format: ~r/@/
        attribute :username, :string, format: ~r/^[a-z_]+$/, max_length: 32
      end

      assert [
               {:email, :string, [format: email_format]},
               {:username, :string, [format: username_format, max_length: 32]}
             ] = InlineEntityFixture51.__attributes__()

      assert Regex.source(email_format) == "@"
      assert Regex.source(username_format) == "^[a-z_]+$"
    end

    test "rejects format option on non-string attribute type" do
      expected_msg =
        "format option not allowed for attribute :count in Hologram.Entity.ValidatorTest.InlineEntityFixture52 - the format option applies only to string attributes"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture52 do
          use Hologram.Entity

          attribute :count, :integer, format: ~r/\d+/
        end
      end
    end

    test "rejects non-regex format option" do
      expected_msg =
        "invalid format option \"@\" for attribute :email in Hologram.Entity.ValidatorTest.InlineEntityFixture53 - the format option must be a Regex"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture53 do
          use Hologram.Entity

          attribute :email, :string, format: "@"
        end
      end
    end

    test "rejects default violating declared constraints" do
      expected_msg =
        "invalid default value 0 for attribute :count in Hologram.Entity.ValidatorTest.InlineEntityFixture54 - the default value doesn't satisfy the min option 1"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture54 do
          use Hologram.Entity

          attribute :count, :integer, min: 1, default: 0
        end
      end
    end

    test "rejects duplicate attribute name" do
      expected_msg =
        "duplicate name :title used for attribute in Hologram.Entity.ValidatorTest.InlineEntityFixture3 - attribute and relationship names share one namespace and must be unique"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture3 do
          use Hologram.Entity

          attribute :title, :string
          attribute :title, :integer
        end
      end
    end

    test "rejects attribute colliding with a to-one reference field" do
      expected_msg =
        "attribute :owner_id in Hologram.Entity.ValidatorTest.InlineEntityFixture26 derives entity field :owner_id, which collides with relationship :owner - every declaration must derive distinct fields"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture26 do
          use Hologram.Entity

          relationship :owner, Module1
          attribute :owner_id, :string
        end
      end
    end

    test "rejects attribute name already used by relationship" do
      expected_msg =
        "duplicate name :owner used for attribute in Hologram.Entity.ValidatorTest.InlineEntityFixture4 - attribute and relationship names share one namespace and must be unique"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture4 do
          use Hologram.Entity

          relationship :owner, Module1

          attribute :owner, :string
        end
      end
    end

    test "rejects enum attribute without values option" do
      expected_msg =
        "missing values option for enum attribute :status in Hologram.Entity.ValidatorTest.InlineEntityFixture7 - enum attributes require a values option with a non-empty list of unique non-nil atoms"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture7 do
          use Hologram.Entity

          attribute :status, :enum
        end
      end
    end

    test "rejects enum default outside declared values" do
      expected_msg =
        "invalid default value :c for enum attribute :status in Hologram.Entity.ValidatorTest.InlineEntityFixture14 - the default value must be one of the declared values or nil when the attribute is optional"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture14 do
          use Hologram.Entity

          attribute :status, :enum, values: [:a, :b], default: :c
        end
      end
    end

    test "rejects invalid enum values option" do
      invalid_values = [[], [:a, :a], [:a, nil], ["x", "y"], :not_a_list]

      for {values, index} <- Enum.with_index(invalid_values) do
        module_name = "Hologram.Entity.ValidatorTest.InvalidEnumValues#{index}"

        expected_msg =
          "invalid values option #{inspect(values)} for enum attribute :status in #{module_name} - the values option must be a non-empty list of unique non-nil atoms"

        code = """
        defmodule #{module_name} do
          use Hologram.Entity

          attribute :status, :enum, values: #{inspect(values)}
        end
        """

        assert_error Hologram.CompileError, expected_msg, fn -> Code.eval_string(code) end
      end
    end

    test "rejects non-boolean optional option" do
      expected_msg =
        "invalid optional option :yes for attribute :title in Hologram.Entity.ValidatorTest.InlineEntityFixture9 - the optional option must be true or false"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture9 do
          use Hologram.Entity

          attribute :title, :string, optional: :yes
        end
      end
    end

    test "rejects non-atom attribute name" do
      expected_msg =
        "invalid name \"title\" used for attribute in Hologram.Entity.ValidatorTest.InlineEntityFixture15 - declaration names must be atoms"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture15 do
          use Hologram.Entity

          attribute "title", :string
        end
      end
    end

    test "rejects non-keyword options" do
      expected_msg =
        "invalid options %{optional: true} for attribute :title in Hologram.Entity.ValidatorTest.InlineEntityFixture20 - options must be a keyword list"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture20 do
          use Hologram.Entity

          attribute :title, :string, %{optional: true}
        end
      end
    end

    test "rejects reserved system attribute names" do
      for reserved_name <- [:created_at, :id, :updated_at] do
        module_name =
          "Hologram.Entity.ValidatorTest.ReservedAttr#{Macro.camelize(to_string(reserved_name))}"

        expected_msg =
          "reserved name #{inspect(reserved_name)} used for attribute in #{module_name} - system attributes :created_at, :id, :updated_at are managed automatically and can't be declared"

        code = """
        defmodule #{module_name} do
          use Hologram.Entity

          attribute :#{reserved_name}, :string
        end
        """

        assert_error Hologram.CompileError, expected_msg, fn -> Code.eval_string(code) end
      end
    end
  end

  describe "validate_changes/2" do
    test "returns :ok for valid present pairs" do
      assert validate_changes(Module10, %{count: 5, username: "abcd"}) == :ok
    end

    test "does not require absent attributes" do
      assert validate_changes(Module2, %{}) == :ok
      assert validate_changes(Module2, %{b: 2}) == :ok
    end

    test "accepts nil for optional attribute" do
      assert validate_changes(Module2, %{b: nil}) == :ok
    end

    test "reports required violation for nil non-optional value" do
      assert validate_changes(Module2, %{c: nil}) == {:error, [{:c, :required}]}
    end

    test "reports type and constraint violations" do
      assert validate_changes(Module10, %{count: 0, username: 5}) ==
               {:error, [{:count, {:min, 1}}, {:username, {:type, :string}}]}
    end

    test "validates reference field pairs" do
      target_id = "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f"

      assert validate_changes(Module3, %{c_id: target_id}) == :ok
      assert validate_changes(Module3, %{b_id: nil}) == :ok
      assert validate_changes(Module3, %{c_id: nil}) == {:error, [{:c_id, :required}]}
      assert validate_changes(Module3, %{c_id: "garbage"}) == {:error, [{:c_id, {:type, :uuid}}]}
    end

    test "reports unknown names" do
      assert validate_changes(Module2, %{e: 1}) == {:error, [{:e, :unknown}]}
    end
  end

  describe "validate_model!/1" do
    test "returns :ok for empty model" do
      assert validate_model!([]) == :ok
    end

    test "returns :ok when every relationship target is an entity type module" do
      assert validate_model!([Module1, Module2, Module3]) == :ok
    end

    test "rejects a relationship targeting a non-entity module" do
      defmodule InlineEntityFixture22 do
        use Hologram.Entity

        relationship :owner, Hologram.Reflection
      end

      expected_msg =
        "invalid data model:\n  * relationship :owner in Hologram.Entity.ValidatorTest.InlineEntityFixture22 targets Hologram.Reflection, which is not an entity type module"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlineEntityFixture22])
      end
    end

    test "rejects a relationship targeting a nonexistent module" do
      defmodule InlineEntityFixture23 do
        use Hologram.Entity

        relationship :owner, NonExistent.Module
      end

      expected_msg =
        "invalid data model:\n  * relationship :owner in Hologram.Entity.ValidatorTest.InlineEntityFixture23 targets NonExistent.Module, which is not an entity type module"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlineEntityFixture23])
      end
    end

    test "collects all violations across the model and raises once" do
      defmodule InlineEntityFixture24 do
        use Hologram.Entity

        relationship :a, Hologram.Reflection
      end

      defmodule InlineEntityFixture25 do
        use Hologram.Entity

        relationship :b, [NonExistent.Module]
        relationship :c, Module2
      end

      expected_msg =
        "invalid data model:\n  * relationship :a in Hologram.Entity.ValidatorTest.InlineEntityFixture24 targets Hologram.Reflection, which is not an entity type module\n  * relationship :b in Hologram.Entity.ValidatorTest.InlineEntityFixture25 targets NonExistent.Module, which is not an entity type module"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_model!([InlineEntityFixture24, InlineEntityFixture25])
      end
    end
  end

  describe "validate_relationship!/4" do
    test "rejects a to-one reference field colliding with an attribute" do
      expected_msg =
        "relationship :owner in Hologram.Entity.ValidatorTest.InlineEntityFixture27 derives entity field :owner_id, which collides with attribute :owner_id - every declaration must derive distinct fields"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture27 do
          use Hologram.Entity

          attribute :owner_id, :string
          relationship :owner, Module1
        end
      end
    end

    test "rejects duplicate relationship name" do
      expected_msg =
        "duplicate name :owner used for relationship in Hologram.Entity.ValidatorTest.InlineEntityFixture5 - attribute and relationship names share one namespace and must be unique"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture5 do
          use Hologram.Entity

          relationship :owner, Module1
          relationship :owner, Module2
        end
      end
    end

    test "rejects relationship name already used by attribute" do
      expected_msg =
        "duplicate name :title used for relationship in Hologram.Entity.ValidatorTest.InlineEntityFixture6 - attribute and relationship names share one namespace and must be unique"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture6 do
          use Hologram.Entity

          attribute :title, :string

          relationship :title, Module1
        end
      end
    end

    test "rejects non-boolean optional option" do
      expected_msg =
        "invalid optional option 1 for relationship :owner in Hologram.Entity.ValidatorTest.InlineEntityFixture11 - the optional option must be true or false"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture11 do
          use Hologram.Entity

          relationship :owner, Module1, optional: 1
        end
      end
    end

    test "rejects non-atom relationship name" do
      expected_msg =
        "invalid name \"owner\" used for relationship in Hologram.Entity.ValidatorTest.InlineEntityFixture16 - declaration names must be atoms"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture16 do
          use Hologram.Entity

          relationship "owner", Module1
        end
      end
    end

    test "rejects non-keyword options" do
      expected_msg =
        "invalid options [:optional] for relationship :owner in Hologram.Entity.ValidatorTest.InlineEntityFixture21 - options must be a keyword list"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture21 do
          use Hologram.Entity

          relationship :owner, Module1, [:optional]
        end
      end
    end

    test "rejects reserved system attribute names" do
      for reserved_name <- [:created_at, :id, :updated_at] do
        module_name =
          "Hologram.Entity.ValidatorTest.ReservedRelationship#{Macro.camelize(to_string(reserved_name))}"

        expected_msg =
          "reserved name #{inspect(reserved_name)} used for relationship in #{module_name} - system attributes :created_at, :id, :updated_at are managed automatically and can't be declared"

        code = """
        defmodule #{module_name} do
          use Hologram.Entity

          relationship :#{reserved_name}, Hologram.Test.Fixtures.Entity.Module1
        end
        """

        assert_error Hologram.CompileError, expected_msg, fn -> Code.eval_string(code) end
      end
    end

    test "rejects invalid relationship type shape" do
      invalid_types = [
        ":string",
        "\"Task\"",
        "5",
        "[]",
        "[Hologram.Test.Fixtures.Entity.Module1, Hologram.Test.Fixtures.Entity.Module2]"
      ]

      for {type_code, index} <- Enum.with_index(invalid_types) do
        module_name = "Hologram.Entity.ValidatorTest.InvalidRelationshipType#{index}"

        {type_value, _binding} = Code.eval_string(type_code)

        expected_msg =
          "invalid type #{inspect(type_value)} for relationship :owner in #{module_name} - the relationship type must be an entity type module (to-one) or a one-element list wrapping an entity type module (to-many)"

        code = """
        defmodule #{module_name} do
          use Hologram.Entity

          relationship :owner, #{type_code}
        end
        """

        assert_error Hologram.CompileError, expected_msg, fn -> Code.eval_string(code) end
      end
    end

    test "rejects unknown relationship option" do
      expected_msg =
        "unknown option :default for relationship :owner in Hologram.Entity.ValidatorTest.InlineEntityFixture12 - valid relationship options are: :optional"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture12 do
          use Hologram.Entity

          relationship :owner, Module1, default: nil
        end
      end
    end
  end
end
