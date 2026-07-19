defmodule Hologram.EntityTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module4

  describe "__attributes__/0" do
    test "returns empty list for entity type with no attribute declarations" do
      assert Module1.__attributes__() == []
    end

    test "returns attribute definitions sorted by name regardless of declaration order" do
      assert Module2.__attributes__() == [
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

  describe "__struct__/0" do
    test "defines only system attribute fields for entity type with no declarations" do
      field_names =
        %Module1{}
        |> Map.from_struct()
        |> Map.keys()
        |> Enum.sort()

      assert field_names == [:created_at, :id, :updated_at]
    end

    test "includes declared attribute fields" do
      field_names =
        %Module2{}
        |> Map.from_struct()
        |> Map.keys()
        |> Enum.sort()

      assert field_names == [:a, :b, :c, :created_at, :id, :updated_at]
    end

    test "includes to-one relationship fields and excludes to-many relationship fields" do
      field_names =
        %Module3{}
        |> Map.from_struct()
        |> Map.keys()
        |> Enum.sort()

      assert field_names == [:b, :c, :created_at, :id, :updated_at]
    end
  end

  describe "__system_attributes__/0" do
    test "returns system attribute definitions sorted by name on every entity type" do
      expected = [
        {:created_at, :datetime, []},
        {:id, :uuid, []},
        {:updated_at, :datetime, []}
      ]

      assert Module1.__system_attributes__() == expected
      assert Module2.__system_attributes__() == expected
    end
  end

  describe "attribute/3" do
    test "accepts all valid attribute types" do
      assert Module4.__attributes__() == [
               {:a, :date, []},
               {:b, :datetime, []},
               {:c, :enum, [values: [:x, :y], default: :x]},
               {:d, :float, []}
             ]
    end
  end

  # IMPORTANT!
  # Each test in this describe block has a related JavaScript test in test/javascript/utils_test.mjs (describe "uuidv7()")
  # Always update both together.
  describe "generate_id/0" do
    test "returns a version 7 UUID string" do
      assert generate_id() =~
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/
    end

    test "returns a different id on each call" do
      assert generate_id() != generate_id()
    end

    test "embeds the number of milliseconds since the Unix epoch in the leading bits" do
      unix_ms_before = System.system_time(:millisecond)
      id = generate_id()
      unix_ms_after = System.system_time(:millisecond)

      embedded_unix_ms =
        id
        |> String.replace("-", "")
        |> String.slice(0, 12)
        |> String.to_integer(16)

      assert embedded_unix_ms >= unix_ms_before
      assert embedded_unix_ms <= unix_ms_after
    end
  end

  describe "new/2" do
    test "returns a struct of the given entity type with a generated id and nil system timestamps" do
      entity = new(Module1)

      assert is_struct(entity, Module1)

      assert entity.id =~
               ~r/^[0-9a-f]{8}-[0-9a-f]{4}-7[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/

      assert entity.created_at == nil
      assert entity.updated_at == nil
    end

    test "applies declared defaults to absent attributes" do
      entity = new(Module2)

      assert entity.a == false
      assert entity.b == nil
      assert entity.c == nil
    end

    test "keeps given attribute values over declared defaults" do
      assert new(Module2, %{a: true}).a == true
    end

    test "accepts values as a map" do
      assert new(Module2, %{c: "text_1"}).c == "text_1"
    end

    test "accepts values as a keyword list" do
      assert new(Module2, c: "text_2").c == "text_2"
    end

    test "keeps a given id" do
      assert new(Module2, %{id: "id_1"}).id == "id_1"
    end

    test "sets given to-one relationship references" do
      assert new(Module3, %{c: "id_2"}).c == "id_2"
    end
  end
end
