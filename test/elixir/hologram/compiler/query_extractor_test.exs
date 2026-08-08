defmodule Hologram.Compiler.QueryExtractorTest do
  use Hologram.Test.BasicCase, async: true
  use Hologram.Query

  import Hologram.Compiler.QueryExtractor

  alias Hologram.Query
  alias Hologram.Query.Param
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module1
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module2
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module3
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module4
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module6
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module7
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module8
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module9
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module10
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module11
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module12
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module13
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module14
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module15
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  describe "extract_module_queries/1" do
    test "extracts a query registered through a cross-module capture" do
      expected_term =
        Entity2
        |> filter(b: 123)
        |> Query.normalize()

      assert extract_module_queries(Module4) == [expected_term]
    end

    test "extracts a zero-arity capture branching on compile-time values" do
      expected_term =
        Entity2
        |> filter(b: {:>=, 17})
        |> Query.normalize()

      assert extract_module_queries(Module12) == [expected_term]
    end

    test "extracts normalized terms from from_query props" do
      expected_term =
        Entity2
        |> filter(a: true)
        |> order_by(:c)
        |> Query.normalize()

      assert extract_module_queries(Module1) == [expected_term]
    end

    test "extracts params from a local parameterized capture through its shim" do
      expected_term =
        Entity2
        |> filter(b: {:>=, %Param{name: :min_b}})
        |> Query.normalize()

      assert extract_module_queries(Module2) == [expected_term]
    end

    test "extracts params from a remote parameterized capture in argument order" do
      expected_term =
        Entity2
        |> filter(b: {:>=, %Param{name: :min_b}}, c: %Param{name: :search})
        |> Query.normalize()

      assert extract_module_queries(Module6) == [expected_term]
    end

    test "extracts through variable binds and concrete native calls" do
      expected_term =
        Entity2
        |> filter(a: true)
        |> filter(b: {:>=, %Param{name: :min_b}}, c: "ABC")
        |> Query.normalize()

      assert extract_module_queries(Module15) == [expected_term]
    end

    test "yields no terms for modules without prop declarations" do
      assert extract_module_queries(Entity2) == []
    end

    test "raises on a destructured query capture argument" do
      expected_msg =
        "query capture for prop :entities in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module8 destructures an argument - arguments must be plain names, each binding to the like-named component assign"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_module_queries(Module8)
      end
    end

    test "raises on a guarded parameterized capture clause" do
      expected_msg =
        "query capture for prop :entities in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module10 has a guarded clause - branching parameterized builders are not extractable yet"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_module_queries(Module10)
      end
    end

    test "raises on a local function call in a parameterized capture" do
      expected_msg =
        "query capture for prop :entities in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module14 calls local function bounded_query/1 - helper composition is not extractable yet"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_module_queries(Module14)
      end
    end

    test "raises on a multi-clause parameterized capture" do
      expected_msg =
        "query capture for prop :entities in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module9 has multiple clauses - branching parameterized builders are not extractable yet"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_module_queries(Module9)
      end
    end

    test "raises on a non-capture from_query value" do
      expected_msg =
        "from_query for prop :entities in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module3 must be a function capture, got: 123"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_module_queries(Module3)
      end
    end

    test "raises on a parameterized capture branching in its body" do
      expected_msg =
        "query capture for prop :entities in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module11 branches in its body - branching parameterized builders are not extractable yet"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_module_queries(Module11)
      end
    end

    test "raises on a query capture argument named vars" do
      expected_msg =
        "query capture for prop :entities in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module7 names an argument vars - the name is reserved, name arguments after the component assigns they bind to"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_module_queries(Module7)
      end
    end

    test "raises on an argument passed to a non-stage call" do
      expected_msg =
        "query capture for prop :entities in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module13 passes an argument to String.downcase/1 - arguments must flow directly into query stage calls, computing on them is not extractable yet"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_module_queries(Module13)
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
