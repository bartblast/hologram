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

      expected =
        normalize_newlines("""
        invalid data for Hologram.Test.Fixtures.Entity.Module10:
          * attribute :count must be at least 1, got: 0
          * attribute :priority must be in 1..5, got: 9\
        """)

      assert error_message(Module10, data, errors) == expected
    end

    test "describes required and unknown violations without received values" do
      data = %{b: 1, e: 2}
      {:error, errors} = validate(Module2, data)

      expected =
        normalize_newlines("""
        invalid data for Hologram.Test.Fixtures.Entity.Module2:
          * attribute :a is required
          * attribute :c is required
          * :e is not a declared attribute or to-one reference\
        """)

      assert error_message(Module2, data, errors) == expected
    end

    test "describes reference violations with reference wording" do
      required_data = %{}
      {:error, required_errors} = validate(Module3, required_data)

      expected_required =
        normalize_newlines("""
        invalid data for Hologram.Test.Fixtures.Entity.Module3:
          * reference :c_id is required\
        """)

      assert error_message(Module3, required_data, required_errors) == expected_required

      invalid_data = %{c_id: "garbage"}
      {:error, invalid_errors} = validate(Module3, invalid_data)

      expected_invalid =
        normalize_newlines("""
        invalid data for Hologram.Test.Fixtures.Entity.Module3:
          * reference :c_id must be a valid entity id, got: "garbage"\
        """)

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

      expected =
        normalize_newlines("""
        invalid data for Hologram.Test.Fixtures.Entity.Module10:
          * attribute :bio must be at most 10 characters, got: "01234567890"
          * attribute :country_code must be exactly 2 characters, got: "USA"
          * attribute :email must match ~r/@/, got: "nope"
          * attribute :held_at must be at most ~U[2026-12-31 23:59:59Z], got: ~U[2027-01-01 00:00:00Z]
          * attribute :rating must be of type :float, got: "high"
          * attribute :status must be one of [:draft, :published], got: "x"
          * attribute :username must be at least 3 characters, got: "ab"\
        """)

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

  describe "validate_allow!/3" do
    test "accepts a bare allow line as an unconditional rule" do
      defmodule InlineEntityFixture71 do
        use Hologram.Entity

        allow :read
      end

      assert InlineEntityFixture71.__policies__() == [{:read, nil, nil, []}]
    end

    test "accepts an unknown option as a predicate" do
      defmodule InlineEntityFixture72 do
        use Hologram.Entity

        attribute :title, :string

        allow :read, title: "text_1"
      end

      assert InlineEntityFixture72.__policies__() == [{:read, nil, nil, [title: "text_1"]}]
    end

    test "rejects non-atom operation" do
      expected_msg =
        "invalid operation \"read\" used for allow in Hologram.Entity.ValidatorTest.InlineEntityFixture73 - policy operations must be atoms"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture73 do
          use Hologram.Entity

          allow "read"
        end
      end
    end

    test "rejects a nil to option" do
      expected_msg =
        "invalid to option nil for allow :read in Hologram.Entity.ValidatorTest.NilToOptionFixture - omit the option instead"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule NilToOptionFixture do
          use Hologram.Entity

          allow :read, to: nil
        end
      end
    end

    test "rejects a nil via option" do
      expected_msg =
        "invalid via option nil for allow :read in Hologram.Entity.ValidatorTest.NilViaOptionFixture - omit the option instead"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule NilViaOptionFixture do
          use Hologram.Entity

          allow :read, via: nil
        end
      end
    end

    test "rejects a to option that is neither a role reference nor a list of them" do
      expected_msg =
        "invalid to option \"owner\" for allow :update in Hologram.Entity.ValidatorTest.MalformedToOptionFixture - the to option must be a role name, a {module, role} or {relationship, role} tuple, or a non-empty list of them"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule MalformedToOptionFixture do
          use Hologram.Entity

          role :owner

          allow :update, to: "owner"
        end
      end
    end

    test "rejects a to option list holding a malformed reference" do
      expected_msg =
        "invalid to option [{:a, :b, :c}] for allow :read in Hologram.Entity.ValidatorTest.MalformedToListFixture - the to option must be a role name, a {module, role} or {relationship, role} tuple, or a non-empty list of them"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule MalformedToListFixture do
          use Hologram.Entity

          allow :read, to: [{:a, :b, :c}]
        end
      end
    end

    test "rejects an empty to option list" do
      expected_msg =
        "invalid to option [] for allow :read in Hologram.Entity.ValidatorTest.EmptyToListFixture - the to option must be a role name, a {module, role} or {relationship, role} tuple, or a non-empty list of them"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule EmptyToListFixture do
          use Hologram.Entity

          allow :read, to: []
        end
      end
    end

    test "rejects spec that is not a keyword list" do
      expected_msg =
        "invalid options [1, 2] for allow :read in Hologram.Entity.ValidatorTest.InlineEntityFixture74 - options must be a keyword list"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture74 do
          use Hologram.Entity

          allow :read, [1, 2]
        end
      end
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
        "unknown option :require for attribute :title in Hologram.Entity.ValidatorTest.InlineEntityFixture10 - valid attribute options are: :default, :format, :in, :length, :max, :max_length, :min, :min_length, :optional, :server_only, :unique, :values"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture10 do
          use Hologram.Entity

          attribute :title, :string, require: true
        end
      end
    end

    test "rejects unknown attribute type" do
      expected_msg =
        "invalid type :text for attribute :title in Hologram.Entity.ValidatorTest.InlineEntityFixture1 - valid attribute types are: :boolean, :date, :datetime, :enum, :float, :integer, :string, :uuid"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture1 do
          use Hologram.Entity

          attribute :title, :text
        end
      end
    end

    test "rejects module used as attribute type" do
      expected_msg =
        "invalid type DateTime for attribute :happened_at in Hologram.Entity.ValidatorTest.InlineEntityFixture2 - valid attribute types are: :boolean, :date, :datetime, :enum, :float, :integer, :string, :uuid"

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

    test "accepts uuid attribute" do
      defmodule InlineEntityFixture82 do
        use Hologram.Entity

        attribute :external_id, :uuid, optional: true
      end

      assert InlineEntityFixture82.__attributes__() == [{:external_id, :uuid, [optional: true]}]
    end

    test "accepts attribute named user_id" do
      defmodule InlineEntityFixture75 do
        use Hologram.Entity

        attribute :user_id, :string
      end

      assert InlineEntityFixture75.__attributes__() == [{:user_id, :string, []}]
    end

    test "rejects attribute named to" do
      expected_msg =
        "reserved name :to used for attribute in Hologram.Entity.ValidatorTest.InlineEntityFixture76 - :to and :via are allow line options and can't be attribute names"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture76 do
          use Hologram.Entity

          attribute :to, :string
        end
      end
    end

    test "rejects attribute named via" do
      expected_msg =
        "reserved name :via used for attribute in Hologram.Entity.ValidatorTest.InlineEntityFixture77 - :to and :via are allow line options and can't be attribute names"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture77 do
          use Hologram.Entity

          attribute :via, :string
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

    test "accepts enum values that are modules" do
      defmodule ModuleEnumValuesFixture do
        use Hologram.Entity

        attribute :role, :enum, values: [:viewer, Hologram.Test.Fixtures.Role.Module1]
      end

      assert ModuleEnumValuesFixture.__attributes__() == [
               {:role, :enum, [values: [:viewer, Hologram.Test.Fixtures.Role.Module1]]}
             ]
    end

    test "rejects an enum value that is not a module and does not begin with a lowercase letter" do
      expected_msg =
        "invalid enum value :Active in Hologram.Entity.ValidatorTest.UppercaseEnumValueFixture - enum values that are not modules must begin with a lowercase letter or an underscore"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule UppercaseEnumValueFixture do
          use Hologram.Entity

          attribute :status, :enum, values: [:Active]
        end
      end
    end

    test "rejects an enum value too long to store" do
      expected_msg =
        "enum value :this_is_a_very_long_enum_value_used_to_exceed_the_postgres_enum_label_limit in Hologram.Entity.ValidatorTest.LongEnumValueFixture is too long to store (75 bytes, limit 63) - shorten it"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule LongEnumValueFixture do
          use Hologram.Entity

          attribute :status, :enum,
            values: [
              :this_is_a_very_long_enum_value_used_to_exceed_the_postgres_enum_label_limit
            ]
        end
      end
    end

    test "accepts the server_only option combined with optional and default" do
      defmodule InlineEntityFixture83 do
        use Hologram.Entity

        attribute :archived, :boolean, default: false, server_only: true
        attribute :secret_note, :string, optional: true, server_only: true
      end

      assert InlineEntityFixture83.__attributes__() == [
               {:archived, :boolean, [default: false, server_only: true]},
               {:secret_note, :string, [optional: true, server_only: true]}
             ]
    end

    test "accepts a required server-only attribute" do
      defmodule InlineEntityFixture84 do
        use Hologram.Entity

        attribute :token, :string, server_only: true
      end

      assert InlineEntityFixture84.__attributes__() == [{:token, :string, [server_only: true]}]
    end

    test "accepts a disabled server_only option" do
      defmodule InlineEntityFixture85 do
        use Hologram.Entity

        attribute :title, :string, server_only: false
      end

      assert InlineEntityFixture85.__attributes__() == [{:title, :string, [server_only: false]}]
    end

    test "accepts a unique attribute" do
      defmodule InlineEntityFixture88 do
        use Hologram.Entity

        attribute :slug, :string, unique: true
      end

      assert InlineEntityFixture88.__attributes__() == [{:slug, :string, [unique: true]}]
    end

    test "accepts a disabled unique option" do
      defmodule InlineEntityFixture89 do
        use Hologram.Entity

        attribute :title, :string, unique: false
      end

      assert InlineEntityFixture89.__attributes__() == [{:title, :string, [unique: false]}]
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

    test "rejects non-boolean server_only option" do
      expected_msg =
        "invalid server_only option \"yes\" for attribute :token in Hologram.Entity.ValidatorTest.InlineEntityFixture86 - the server_only option must be true or false"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture86 do
          use Hologram.Entity

          attribute :token, :string, server_only: "yes"
        end
      end
    end

    test "rejects non-boolean unique option" do
      expected_msg =
        "invalid unique option \"yes\" for attribute :slug in Hologram.Entity.ValidatorTest.InlineEntityFixture90 - the unique option must be true or false"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture90 do
          use Hologram.Entity

          attribute :slug, :string, unique: "yes"
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

    test "rejects the server_only option on a relationship" do
      expected_msg =
        "unknown option :server_only for relationship :owner in Hologram.Entity.ValidatorTest.InlineEntityFixture87 - valid relationship options are: :optional"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture87 do
          use Hologram.Entity

          relationship :owner, Module1, server_only: true
        end
      end
    end
  end

  describe "validate_role!/3" do
    test "accepts a role name already used by an attribute" do
      defmodule InlineEntityFixture55 do
        use Hologram.Entity

        attribute :owner, :string

        role :owner
      end

      assert InlineEntityFixture55.__roles__() == [{:owner, []}]
    end

    test "accepts creator option" do
      defmodule InlineEntityFixture68 do
        use Hologram.Entity

        role :owner, creator: true
      end

      assert InlineEntityFixture68.__roles__() == [{:owner, [creator: true]}]
    end

    test "accepts creator option on several roles of one entity type" do
      defmodule InlineEntityFixture69 do
        use Hologram.Entity

        role :author, creator: true
        role :owner, creator: true
      end

      assert InlineEntityFixture69.__roles__() == [
               {:author, [creator: true]},
               {:owner, [creator: true]}
             ]
    end

    test "rejects creator option other than true" do
      expected_msg =
        "invalid creator option false for role :owner in Hologram.Entity.ValidatorTest.InlineEntityFixture70 - the creator option must be true"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture70 do
          use Hologram.Entity

          role :owner, creator: false
        end
      end
    end

    test "rejects non-atom role name" do
      expected_msg =
        "invalid name \"owner\" used for role in Hologram.Entity.ValidatorTest.InlineEntityFixture57 - declaration names must be atoms"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture57 do
          use Hologram.Entity

          role "owner"
        end
      end
    end

    test "rejects a role name that does not begin with a lowercase letter" do
      expected_msg =
        "invalid role name :Owner in Hologram.Entity.ValidatorTest.UppercaseRoleNameFixture - role names that are not modules must begin with a lowercase letter or an underscore"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule UppercaseRoleNameFixture do
          use Hologram.Entity

          role :Owner
        end
      end
    end

    test "rejects a role name too long to store" do
      expected_msg =
        "role name :this_is_a_very_long_role_name_used_to_exceed_the_postgres_enum_label_limit in Hologram.Entity.ValidatorTest.LongRoleNameFixture is too long to store (74 bytes, limit 63) - shorten it"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule LongRoleNameFixture do
          use Hologram.Entity

          role :this_is_a_very_long_role_name_used_to_exceed_the_postgres_enum_label_limit
        end
      end
    end

    test "rejects the removed scope option" do
      expected_msg =
        "scope option for role :admin in Hologram.Entity.ValidatorTest.InlineEntityFixture67 - the scope option was removed, define global roles as modules with use Hologram.Role"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture67 do
          use Hologram.Entity

          role :admin, scope: :global
        end
      end
    end

    test "rejects unknown role option" do
      expected_msg =
        "unknown option :owner_only for role :owner in Hologram.Entity.ValidatorTest.InlineEntityFixture58 - valid role options are: :creator, :extends"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture58 do
          use Hologram.Entity

          role :owner, owner_only: true
        end
      end
    end
  end

  describe "validate_roles!/1" do
    test "accepts a role extending a role declared further down the module body" do
      defmodule InlineEntityFixture59 do
        use Hologram.Entity

        role :owner, extends: :viewer
        role :viewer
      end

      assert InlineEntityFixture59.__roles__() == [{:owner, [extends: :viewer]}, {:viewer, []}]
    end

    test "rejects extends option with a non-atom target in the list" do
      expected_msg =
        "invalid extends option [:viewer, \"editor\"] for role :owner in Hologram.Entity.ValidatorTest.InlineEntityFixture60 - the extends option must be a role name or a non-empty list of role names"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture60 do
          use Hologram.Entity

          role :owner, extends: [:viewer, "editor"]
          role :viewer
        end
      end
    end

    test "rejects empty extends option list" do
      expected_msg =
        "invalid extends option [] for role :owner in Hologram.Entity.ValidatorTest.InlineEntityFixture61 - the extends option must be a role name or a non-empty list of role names"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture61 do
          use Hologram.Entity

          role :owner, extends: []
        end
      end
    end

    test "rejects nil extends option" do
      expected_msg =
        "invalid extends option nil for role :owner in Hologram.Entity.ValidatorTest.NilExtendsFixture - the extends option must be a role name or a non-empty list of role names"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule NilExtendsFixture do
          use Hologram.Entity

          role :owner, extends: nil
        end
      end
    end

    test "rejects role extending an undeclared role" do
      expected_msg =
        "unknown role :editor in the extends option of role :owner in Hologram.Entity.ValidatorTest.InlineEntityFixture62 - declared roles are: :owner, :viewer"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture62 do
          use Hologram.Entity

          role :owner, extends: :editor
          role :viewer
        end
      end
    end

    test "rejects role extension cycle" do
      expected_msg =
        normalize_newlines("""
        cyclic role extension in Hologram.Entity.ValidatorTest.InlineEntityFixture63 - a role can't extend itself, directly or transitively:
          * :editor -> :viewer -> :owner -> :editor\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture63 do
          use Hologram.Entity

          role :editor, extends: :viewer
          role :owner, extends: :editor
          role :viewer, extends: :owner
        end
      end
    end

    test "rejects self-extending role" do
      expected_msg =
        normalize_newlines("""
        cyclic role extension in Hologram.Entity.ValidatorTest.InlineEntityFixture64 - a role can't extend itself, directly or transitively:
          * :owner -> :owner\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture64 do
          use Hologram.Entity

          role :owner, extends: :owner
        end
      end
    end
  end

  describe "validate_use_opts!/2" do
    test "accepts the user option" do
      defmodule InlineEntityFixture78 do
        use Hologram.Entity, user: true
      end

      assert InlineEntityFixture78.__is_hologram_user_entity__()
    end

    test "rejects options that are not a keyword list" do
      expected_msg =
        "invalid options [1, 2] for use Hologram.Entity in Hologram.Entity.ValidatorTest.InlineEntityFixture79 - options must be a keyword list"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture79 do
          use Hologram.Entity, [1, 2]
        end
      end
    end

    test "rejects unknown option" do
      expected_msg =
        "unknown option :usr for use Hologram.Entity in Hologram.Entity.ValidatorTest.InlineEntityFixture80 - valid options are: :user"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture80 do
          use Hologram.Entity, usr: true
        end
      end
    end

    test "rejects user option other than true" do
      expected_msg =
        "invalid user option false for use Hologram.Entity in Hologram.Entity.ValidatorTest.InlineEntityFixture81 - the user option must be true"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture81 do
          use Hologram.Entity, user: false
        end
      end
    end
  end
end
