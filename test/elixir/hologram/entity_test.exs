defmodule Hologram.EntityTest do
  use Hologram.Test.BasicCase, async: true

  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module4

  describe "__attrs__/0" do
    test "returns empty list for entity type with no attribute declarations" do
      assert Module1.__attrs__() == []
    end

    test "returns attribute definitions sorted by name regardless of declaration order" do
      assert Module2.__attrs__() == [
               {:a, :boolean, [default: false]},
               {:b, :integer, [optional: true]},
               {:c, :string, []}
             ]
    end
  end

  test "__is_hologram_entity__/0" do
    assert Module1.__is_hologram_entity__()
  end

  describe "__relationships__/0" do
    test "returns empty list for entity type with no relationship declarations" do
      assert Module1.__relationships__() == []
    end

    test "returns relationship definitions sorted by name regardless of declaration order" do
      assert Module3.__relationships__() == [
               {:a, [Module2], []},
               {:b, Module2, [optional: true]},
               {:c, Module1, []}
             ]
    end
  end

  describe "attr/3" do
    test "accepts all valid attribute types" do
      assert Module4.__attrs__() == [
               {:a, :date, []},
               {:b, :datetime, []},
               {:c, :enum, [values: [:x, :y], default: :x]},
               {:d, :float, []}
             ]
    end

    test "rejects values option on non-enum attribute" do
      expected_msg =
        "values option not allowed for attribute :title in Hologram.EntityTest.InlineEntityFixture8 - the values option applies only to enum attributes"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture8 do
          use Hologram.Entity

          attr :title, :string, values: [:a, :b]
        end
      end
    end

    test "rejects unknown attribute option" do
      expected_msg =
        "unknown option :require for attribute :title in Hologram.EntityTest.InlineEntityFixture10 - valid attribute options are: :default, :optional, :values"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture10 do
          use Hologram.Entity

          attr :title, :string, require: true
        end
      end
    end

    test "rejects unknown attribute type" do
      expected_msg =
        "invalid type :text for attribute :title in Hologram.EntityTest.InlineEntityFixture1 - valid attribute types are: :boolean, :date, :datetime, :enum, :float, :integer, :string"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture1 do
          use Hologram.Entity

          attr :title, :text
        end
      end
    end

    test "rejects module used as attribute type" do
      expected_msg =
        "invalid type DateTime for attribute :happened_at in Hologram.EntityTest.InlineEntityFixture2 - valid attribute types are: :boolean, :date, :datetime, :enum, :float, :integer, :string"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture2 do
          use Hologram.Entity

          attr :happened_at, DateTime
        end
      end
    end

    test "rejects default not matching attribute type" do
      expected_msg =
        "invalid default value 5 for attribute :title in Hologram.EntityTest.InlineEntityFixture13 - the default value must match the attribute type :string"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture13 do
          use Hologram.Entity

          attr :title, :string, default: 5
        end
      end
    end

    test "rejects duplicate attribute name" do
      expected_msg =
        "duplicate name :title used for attribute in Hologram.EntityTest.InlineEntityFixture3 - attribute and relationship names share one namespace and must be unique"

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
        "duplicate name :owner used for attribute in Hologram.EntityTest.InlineEntityFixture4 - attribute and relationship names share one namespace and must be unique"

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
        "missing values option for enum attribute :status in Hologram.EntityTest.InlineEntityFixture7 - enum attributes require a values option with a non-empty list of unique atoms"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture7 do
          use Hologram.Entity

          attr :status, :enum
        end
      end
    end

    test "rejects enum default outside declared values" do
      expected_msg =
        "invalid default value :c for enum attribute :status in Hologram.EntityTest.InlineEntityFixture14 - the default value must be one of the declared values"

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
        module_name = "Hologram.EntityTest.InvalidEnumValues#{index}"

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
        "invalid optional option :yes for attribute :title in Hologram.EntityTest.InlineEntityFixture9 - the optional option must be true or false"

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
          "Hologram.EntityTest.ReservedAttr#{Macro.camelize(to_string(reserved_name))}"

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

  describe "relationship/3" do
    test "rejects duplicate relationship name" do
      expected_msg =
        "duplicate name :owner used for relationship in Hologram.EntityTest.InlineEntityFixture5 - attribute and relationship names share one namespace and must be unique"

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
        "duplicate name :title used for relationship in Hologram.EntityTest.InlineEntityFixture6 - attribute and relationship names share one namespace and must be unique"

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
        "invalid optional option 1 for relationship :owner in Hologram.EntityTest.InlineEntityFixture11 - the optional option must be true or false"

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
          "Hologram.EntityTest.ReservedRelationship#{Macro.camelize(to_string(reserved_name))}"

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
        "unknown option :default for relationship :owner in Hologram.EntityTest.InlineEntityFixture12 - valid relationship options are: :optional"

      assert_error Hologram.CompileError, expected_msg, fn ->
        defmodule InlineEntityFixture12 do
          use Hologram.Entity

          relationship :owner, Module1, default: nil
        end
      end
    end
  end
end
