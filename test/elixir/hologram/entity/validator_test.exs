defmodule Hologram.Entity.ValidatorTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Entity.Validator

  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module2

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

  describe "validate_attr!/4" do
    test "rejects values option on non-enum attribute" do
      expected_msg =
        "values option not allowed for attribute :title in Hologram.Entity.ValidatorTest.InlineEntityFixture8 - the values option applies only to enum attributes"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture8 do
          use Hologram.Entity

          attr :title, :string, values: [:a, :b]
        end
      end
    end

    test "rejects unknown attribute option" do
      expected_msg =
        "unknown option :require for attribute :title in Hologram.Entity.ValidatorTest.InlineEntityFixture10 - valid attribute options are: :default, :optional, :values"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture10 do
          use Hologram.Entity

          attr :title, :string, require: true
        end
      end
    end

    test "rejects unknown attribute type" do
      expected_msg =
        "invalid type :text for attribute :title in Hologram.Entity.ValidatorTest.InlineEntityFixture1 - valid attribute types are: :boolean, :date, :datetime, :enum, :float, :integer, :string"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture1 do
          use Hologram.Entity

          attr :title, :text
        end
      end
    end

    test "rejects module used as attribute type" do
      expected_msg =
        "invalid type DateTime for attribute :happened_at in Hologram.Entity.ValidatorTest.InlineEntityFixture2 - valid attribute types are: :boolean, :date, :datetime, :enum, :float, :integer, :string"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture2 do
          use Hologram.Entity

          attr :happened_at, DateTime
        end
      end
    end

    test "rejects default not matching attribute type" do
      expected_msg =
        "invalid default value 5 for attribute :title in Hologram.Entity.ValidatorTest.InlineEntityFixture13 - the default value must match the attribute type :string"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture13 do
          use Hologram.Entity

          attr :title, :string, default: 5
        end
      end
    end

    test "rejects duplicate attribute name" do
      expected_msg =
        "duplicate name :title used for attribute in Hologram.Entity.ValidatorTest.InlineEntityFixture3 - attribute and relationship names share one namespace and must be unique"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture3 do
          use Hologram.Entity

          attr :title, :string
          attr :title, :integer
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

          attr :owner, :string
        end
      end
    end

    test "rejects enum attribute without values option" do
      expected_msg =
        "missing values option for enum attribute :status in Hologram.Entity.ValidatorTest.InlineEntityFixture7 - enum attributes require a values option with a non-empty list of unique atoms"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture7 do
          use Hologram.Entity

          attr :status, :enum
        end
      end
    end

    test "rejects enum default outside declared values" do
      expected_msg =
        "invalid default value :c for enum attribute :status in Hologram.Entity.ValidatorTest.InlineEntityFixture14 - the default value must be one of the declared values"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture14 do
          use Hologram.Entity

          attr :status, :enum, values: [:a, :b], default: :c
        end
      end
    end

    test "rejects invalid enum values option" do
      invalid_values = [[], [:a, :a], ["x", "y"], :not_a_list]

      for {values, index} <- Enum.with_index(invalid_values) do
        module_name = "Hologram.Entity.ValidatorTest.InvalidEnumValues#{index}"

        expected_msg =
          "invalid values option #{inspect(values)} for enum attribute :status in #{module_name} - the values option must be a non-empty list of unique atoms"

        code = """
        defmodule #{module_name} do
          use Hologram.Entity

          attr :status, :enum, values: #{inspect(values)}
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

          attr :title, :string, optional: :yes
        end
      end
    end

    test "rejects reserved engine attribute names" do
      for reserved_name <- [:created_at, :id, :updated_at] do
        module_name =
          "Hologram.Entity.ValidatorTest.ReservedAttr#{Macro.camelize(to_string(reserved_name))}"

        expected_msg =
          "reserved name #{inspect(reserved_name)} used for attribute in #{module_name} - engine attributes :created_at, :id, :updated_at are managed automatically and can't be declared"

        code = """
        defmodule #{module_name} do
          use Hologram.Entity

          attr :#{reserved_name}, :string
        end
        """

        assert_error Hologram.CompileError, expected_msg, fn -> Code.eval_string(code) end
      end
    end
  end

  describe "validate_relationship!/4" do
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

          attr :title, :string

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

    test "rejects reserved engine attribute names" do
      for reserved_name <- [:created_at, :id, :updated_at] do
        module_name =
          "Hologram.Entity.ValidatorTest.ReservedRelationship#{Macro.camelize(to_string(reserved_name))}"

        expected_msg =
          "reserved name #{inspect(reserved_name)} used for relationship in #{module_name} - engine attributes :created_at, :id, :updated_at are managed automatically and can't be declared"

        code = """
        defmodule #{module_name} do
          use Hologram.Entity

          relationship :#{reserved_name}, Hologram.Test.Fixtures.Entity.Module1
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
