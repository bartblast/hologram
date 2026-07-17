defmodule Hologram.EntityTest do
  use Hologram.Test.BasicCase, async: true

  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module2

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
end
