defmodule Hologram.Database.QueryCompilerTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Database.QueryCompiler

  alias Hologram.Database.Mapper
  alias Hologram.Query
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3

  describe "compile/2" do
    test "selects the mapped columns in physical order" do
      mapping = Mapper.derive!([Module2])
      term = Query.normalize(Module2)

      assert compile(term, mapping) == %{
               params: [],
               sql:
                 ~s(SELECT "id", "a", "b", "c", "created_at", "updated_at" FROM "hologram_data"."test_fixtures_entity_module2")
             }
    end

    test "selects reference columns for to-one relationships" do
      mapping = Mapper.derive!([Module2, Module3])
      term = Query.normalize(Module3)

      assert compile(term, mapping) == %{
               params: [],
               sql:
                 ~s(SELECT "id", "b_id", "c_id", "created_at", "updated_at" FROM "hologram_data"."test_fixtures_entity_module3")
             }
    end
  end
end
