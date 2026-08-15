defmodule Hologram.ModelTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Model

  alias Hologram.Reflection
  alias Hologram.Test.Fixtures.Model.Module1
  alias Hologram.Test.Fixtures.Model.Module2
  alias Hologram.Test.Fixtures.Model.Module3

  describe "hash/0" do
    test "hashes the project's compiled data model" do
      assert hash() == hash(Reflection.list_entities())
    end
  end

  describe "hash/1" do
    test "returns a lowercase hex string of the truncated SHA-256" do
      assert hash([Module1, Module2]) == "a29af21904e29cad605667436f736d37"
    end

    test "the same model hashes the same" do
      assert hash([Module1, Module2]) == hash([Module1, Module2])
    end

    test "entity type order doesn't change the hash" do
      assert hash([Module2, Module1]) == hash([Module1, Module2])
    end

    test "adding an entity type changes the hash" do
      refute hash([Module1, Module2]) == hash([Module1])
    end

    test "adding an attribute changes the hash" do
      baseline = hash([Module1])

      Process.put({Module1, :attributes}, [{:title, :string, []}, {:done, :boolean, []}])

      refute hash([Module1]) == baseline
    end

    test "changing an attribute's type changes the hash" do
      baseline = hash([Module1])

      Process.put({Module1, :attributes}, [{:title, :integer, []}])

      refute hash([Module1]) == baseline
    end

    test "changing an attribute's options changes the hash" do
      baseline = hash([Module1])

      Process.put({Module1, :attributes}, [{:title, :string, [server_only: true]}])

      refute hash([Module1]) == baseline
    end

    test "attribute order doesn't change the hash" do
      Process.put({Module1, :attributes}, [{:done, :boolean, []}, {:title, :string, []}])
      one_order = hash([Module1])

      Process.put({Module1, :attributes}, [{:title, :string, []}, {:done, :boolean, []}])

      assert hash([Module1]) == one_order
    end

    test "adding a relationship changes the hash" do
      baseline = hash([Module1])

      Process.put({Module1, :relationships}, [{:author, Module2, []}])

      refute hash([Module1]) == baseline
    end

    test "changing a relationship's target changes the hash" do
      Process.put({Module1, :relationships}, [{:author, Module2, []}])
      baseline = hash([Module1])

      Process.put({Module1, :relationships}, [{:author, Module1, []}])

      refute hash([Module1]) == baseline
    end

    test "an attribute option holding a regex hashes the same on every call" do
      assert hash([Module3]) == hash([Module3])
    end

    test "changing an attribute option's regex changes the hash" do
      baseline = hash([Module3])

      Process.put({Module3, :regex_source}, "^[a-z]+@")

      refute hash([Module3]) == baseline
    end

    test "changing a system attribute changes the hash" do
      baseline = hash([Module1])

      Process.put({Module1, :system_attributes}, [{:id, :uuid, []}])

      refute hash([Module1]) == baseline
    end

    test "policies and roles don't feed the hash" do
      assert hash([Module1]) =~ ~r/^[0-9a-f]{32}$/
    end
  end
end
