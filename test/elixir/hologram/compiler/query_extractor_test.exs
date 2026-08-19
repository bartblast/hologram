defmodule Hologram.Compiler.QueryExtractorTest do
  use Hologram.Test.BasicCase, async: true
  use Hologram.Query

  import Hologram.Compiler.QueryExtractor

  alias Hologram.Query
  alias Hologram.Query.Param
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module1
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module10
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module11
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module12
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module13
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module14
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module15
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module16
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module17
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module18
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module2
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module20
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module21
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module22
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module23
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module24
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module26
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module3
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module4
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module6
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module7
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module8
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module9
  alias Hologram.Test.Fixtures.Component.Module10, as: Component10
  alias Hologram.Test.Fixtures.Component.Module11, as: Component11
  alias Hologram.Test.Fixtures.Component.Module12, as: Component12
  alias Hologram.Test.Fixtures.Component.Module14, as: Component14
  alias Hologram.Test.Fixtures.Component.Module22, as: Component22
  alias Hologram.Test.Fixtures.Component.Module23, as: Component23
  alias Hologram.Test.Fixtures.Component.Module25, as: Component25
  alias Hologram.Test.Fixtures.Component.Module27, as: Component27
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2
  alias Hologram.Test.Fixtures.Entity.Module3, as: Entity3

  describe "extract_module_queries/1" do
    test "extracts a guarded capture ignoring the guard" do
      expected_term =
        Entity2
        |> filter(b: {:>=, %Param{name: :min_b}})
        |> Query.normalize()

      assert extract_module_queries(Module10) == [expected_term]
    end

    test "extracts a param as a membership list element" do
      expected_term =
        Entity2
        |> filter(b: [%Param{name: :min_b}, 1])
        |> Query.normalize()

      assert extract_module_queries(Module26) == [expected_term]
    end

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
        |> filter(b: {:>=, 100})
        |> Query.normalize()

      assert extract_module_queries(Module12) == [expected_term]
    end

    test "extracts an anonymous sub-builder include" do
      expected_term =
        Entity3
        |> include(:a, fn sub -> filter(sub, b: {:>=, %Param{name: :min_b}}) end)
        |> Query.normalize()

      assert extract_module_queries(Module20) == [expected_term]
    end

    test "extracts each clause of a multi-clause capture as a variant" do
      nil_clause_term =
        Entity2
        |> filter(a: true)
        |> Query.normalize()

      bound_clause_term =
        Entity2
        |> filter(b: {:>=, %Param{name: :min_b}})
        |> Query.normalize()

      assert extract_module_queries(Module9) == [nil_clause_term, bound_clause_term]
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

    test "extracts params from an inline from_query function" do
      expected_term =
        Entity2
        |> filter(b: {:>=, %Param{name: :min_b}})
        |> Query.normalize()

      assert extract_module_queries(Module23) == [expected_term]
    end

    test "extracts through a cross-module helper forking its clauses" do
      nil_clause_term =
        Entity2
        |> filter(a: true)
        |> Query.normalize()

      bound_clause_term =
        Entity2
        |> filter(b: {:>=, %Param{name: :min_b}})
        |> Query.normalize()

      assert extract_module_queries(Module18) == [nil_clause_term, bound_clause_term]
    end

    test "extracts through a local helper" do
      expected_term =
        Entity2
        |> filter(b: {:>=, %Param{name: :min_b}})
        |> Query.normalize()

      assert extract_module_queries(Module14) == [expected_term]
    end

    test "extracts through variable binds and concrete native calls" do
      expected_term =
        Entity2
        |> filter(a: true)
        |> filter(b: {:>=, %Param{name: :min_b}}, c: "ABC")
        |> Query.normalize()

      assert extract_module_queries(Module15) == [expected_term]
    end

    test "forks a case on a param into per-clause variants" do
      any_clause_term = Query.normalize(Entity2)

      other_clause_term =
        Entity2
        |> filter(c: %Param{name: :status})
        |> Query.normalize()

      assert extract_module_queries(Module17) == [any_clause_term, other_clause_term]
    end

    test "forks a cond into per-clause variants" do
      bound_clause_term =
        Entity2
        |> filter(b: {:>=, %Param{name: :min_b}})
        |> Query.normalize()

      fallback_clause_term =
        Entity2
        |> filter(a: true)
        |> Query.normalize()

      assert extract_module_queries(Module16) == [bound_clause_term, fallback_clause_term]
    end

    test "forks an if into per-branch variants" do
      else_branch_term =
        Entity2
        |> filter(a: true)
        |> Query.normalize()

      then_branch_term =
        Entity2
        |> filter(b: {:>=, %Param{name: :min_b}})
        |> Query.normalize()

      assert extract_module_queries(Module11) == [else_branch_term, then_branch_term]
    end

    test "yields no terms for modules without prop declarations" do
      assert extract_module_queries(Entity2) == []
    end

    test "raises on a call to an undefined function" do
      expected_msg =
        "query capture for prop :entities in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module24 calls undefined function Hologram.Test.Fixtures.Compiler.QueryExtractor.Module19.missing_helper/1"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_module_queries(Module24)
      end
    end

    test "raises on a capture targeting an undefined function" do
      # Defined at runtime - a compile-time fixture cannot hold a missing-target
      # capture, because the fun value inlined into __props__/0 trips the
      # compiler's undefined-remote warning.
      code = ~s'''
      defmodule Hologram.Compiler.QueryExtractorTest.UndefinedTargetFixture do
        use Hologram.Component

        alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module19
        alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

        prop :entities, [Entity2], from_query: Function.capture(Module19, :missing_query, 1)

        @impl Component
        def template do
          ~HOLO""
        end
      end
      '''

      {_result, _diagnostics} = Code.with_diagnostics(fn -> Code.compile_string(code) end)

      expected_msg =
        "query capture for prop :entities in Hologram.Compiler.QueryExtractorTest.UndefinedTargetFixture targets undefined function Hologram.Test.Fixtures.Compiler.QueryExtractor.Module19.missing_query/1"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_module_queries(Hologram.Compiler.QueryExtractorTest.UndefinedTargetFixture)
      end
    end

    test "raises on a destructured query capture argument" do
      expected_msg =
        "query capture for prop :entities in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module8 destructures an argument - arguments must be plain names, each binding to the like-named component assign"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_module_queries(Module8)
      end
    end

    test "raises on a non-capture from_query value" do
      expected_msg =
        "from_query for prop :entities in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module3 must be a function capture, got: 123"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_module_queries(Module3)
      end
    end

    test "raises on a query capture argument named vars" do
      expected_msg =
        "query capture for prop :entities in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module7 names an argument vars - the name is reserved, name arguments after the component assigns they bind to"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_module_queries(Module7)
      end
    end

    test "raises on a recursive helper" do
      expected_msg =
        "query capture for prop :entities in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module21 recursively calls Hologram.Test.Fixtures.Compiler.QueryExtractor.Module21.entities_query/1 - recursive helpers are not extractable"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_module_queries(Module21)
      end
    end

    test "raises on an argument passed to a non-stage call" do
      expected_msg =
        "query capture for prop :entities in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module13 passes an argument to String.downcase/1 - arguments must flow directly into query stage calls, computing on them is not extractable yet"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_module_queries(Module13)
      end
    end

    test "raises on branching inside an anonymous sub-builder" do
      expected_msg =
        "query capture for prop :entities in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module22 branches inside an anonymous function - not extractable yet"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_module_queries(Module22)
      end
    end
  end

  describe "extract_prop_params/1" do
    test "names arguments of a local parameterized capture through its shim" do
      assert extract_prop_params(Component11) == [entities: [:min_b]]
    end

    test "names arguments of a remote parameterized capture merging clauses" do
      assert extract_prop_params(Component14) == [entities: [:min_b]]
    end

    test "names arguments of an inline parameterized function" do
      assert extract_prop_params(Component12) == [entities: [:min_b]]
    end

    test "yields no entries for modules without prop declarations" do
      assert extract_prop_params(Entity2) == []
    end

    test "yields no entries for zero-arity captures" do
      assert extract_prop_params(Module1) == []
    end

    test "raises when clauses name one argument position differently" do
      expected_msg =
        "query capture for prop :entities in Hologram.Test.Fixtures.Component.Module25 names argument 1 differently across its clauses (:min_b, :max_b) - one argument position binds one prop, and which prop it is has to be known before any clause is chosen, so every clause must name it alike. Rename them to the prop this argument binds, leave the position a literal or an underscored name in the clauses that do not use it, or bind through an adapter naming it once: from_query: fn min_b -> your_query(min_b) end"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_prop_params(Component25)
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

  describe "validate_slot_bindings!/1" do
    test "passes a capture binding declared props" do
      assert validate_slot_bindings!(Component22) == :ok
    end

    test "passes a module without prop declarations" do
      assert validate_slot_bindings!(Entity2) == :ok
    end

    test "passes a zero-arity capture" do
      assert validate_slot_bindings!(Component10) == :ok
    end

    test "raises when a local capture argument binds no declared prop" do
      expected_msg =
        "from_query for prop :entities in Hologram.Test.Fixtures.Component.Module11 binds argument :min_b - no like-named prop is declared"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_slot_bindings!(Component11)
      end
    end

    # A shared builder's argument names are a cross-module contract - each consumer is validated
    # against its own declared slots.
    test "raises when a remote capture argument binds no declared prop" do
      expected_msg =
        "from_query for prop :entities in Hologram.Test.Fixtures.Component.Module14 binds argument :min_b - no like-named prop is declared"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_slot_bindings!(Component14)
      end
    end

    # Slots are what a component is GIVEN. A query's answer is not that, and binding one would
    # make a query depend on another query with nothing ordering the two - the injector runs them
    # in declaration order, so the same pair resolves or raises by which was written first.
    test "raises when a capture argument binds a from_query prop of the same component" do
      expected_msg =
        "from_query for prop :derived in Hologram.Test.Fixtures.Component.Module27 binds argument :entities, which is a from_query prop of the same component - a query argument binds a value the component is GIVEN, never one another query produced"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_slot_bindings!(Component27)
      end
    end

    test "raises when an argument position is named by no clause" do
      expected_msg =
        "from_query capture for prop :entities in Hologram.Test.Fixtures.Component.Module23 has an argument position no clause names - it cannot bind a prop"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_slot_bindings!(Component23)
      end
    end
  end
end
