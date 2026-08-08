defmodule Hologram.Compiler.QueryExtractorTest do
  use Hologram.Test.BasicCase, async: true
  use Hologram.Query

  import Hologram.Compiler.QueryExtractor

  alias Hologram.Query
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module1
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module2
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module3
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module4
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  describe "extract_module_queries/1" do
    test "extracts a query registered through a cross-module capture" do
      expected_term =
        Entity2
        |> filter(b: 123)
        |> Query.normalize()

      assert extract_module_queries(Module4) == [expected_term]
    end

    test "extracts normalized terms from from_query props" do
      expected_term =
        Entity2
        |> filter(a: true)
        |> order_by(:c)
        |> Query.normalize()

      assert extract_module_queries(Module1) == [expected_term]
    end

    test "yields no terms for modules without prop declarations" do
      assert extract_module_queries(Entity2) == []
    end

    test "raises on a non-capture from_query value" do
      expected_msg =
        "from_query for prop :entities in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module3 must be a function capture, got: 123"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_module_queries(Module3)
      end
    end

    test "raises on a parameterized query capture" do
      expected_msg =
        "query capture for prop :entities in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module2 takes arguments - parameterized query captures are not extractable yet"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_module_queries(Module2)
      end
    end
  end

  describe "extract_queries/1" do
    test "collects queries from the given modules in order, skipping query-less ones" do
      module_1_term =
        Entity2
        |> filter(a: true)
        |> order_by(:c)
        |> Query.normalize()

      module_4_term =
        Entity2
        |> filter(b: 123)
        |> Query.normalize()

      assert extract_queries([Module1, Entity2, Module4]) == [module_1_term, module_4_term]
    end
  end
end
