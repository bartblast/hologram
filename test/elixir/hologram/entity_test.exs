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
               {:c, :enum, [values: [:x, :y]]},
               {:d, :float, []}
             ]
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
  end
end
