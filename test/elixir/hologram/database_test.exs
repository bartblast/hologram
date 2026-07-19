defmodule Hologram.DatabaseTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Database

  alias Hologram.Database.Mapper
  alias Hologram.Reflection

  describe "mapping/0" do
    test "returns the mapping derived from the discovered entity types" do
      assert mapping() == Mapper.derive!(Reflection.list_entities())
    end
  end

  describe "pool_name/0" do
    test "names a running connection pool that executes queries" do
      assert Postgrex.query!(pool_name(), "SELECT 1", []).rows == [[1]]
    end
  end
end
