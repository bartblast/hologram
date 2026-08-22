defmodule Hologram.Compiler.QueryExtractorTest do
  use Hologram.Test.BasicCase, async: true
  use Hologram.Query

  import Hologram.Compiler.QueryExtractor

  alias Hologram.Query
  alias Hologram.Query.Placeholder
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
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module27
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module28
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module29
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module3
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module30
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module31
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module32
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module33
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module34
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module35
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module36
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module37
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module38
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module39
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module4
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module40
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module41
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module42
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module43
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module44
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
  alias Hologram.Test.Fixtures.Entity.Module13, as: Entity13
  alias Hologram.Test.Fixtures.Entity.Module18, as: Entity18
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2
  alias Hologram.Test.Fixtures.Entity.Module3, as: Entity3
  alias Hologram.Test.Fixtures.Entity.Module4, as: Entity4

  # A frame opens with the application it came from, which carries the framework's version - the
  # one part of an expected message that cannot be spelled out and stay true across a release.
  @app "(hologram #{Application.spec(:hologram, :vsn)})"

  describe "extract_module_queries/1" do
    test "extracts a derived placeholder from a nested argument field read" do
      expected_term =
        Entity2
        |> filter(c: %Placeholder{name: :"entity.b.c"})
        |> Query.normalize()

      assert extract_module_queries(Module28) == [expected_term]
    end

    test "extracts a derived placeholder from an argument field read" do
      expected_term =
        Entity2
        |> filter(b: %Placeholder{name: :"entity.b"})
        |> Query.normalize()

      assert extract_module_queries(Module27) == [expected_term]
    end

    test "extracts a field read on a concrete map" do
      expected_term =
        Entity2
        |> filter(b: {:>=, %Placeholder{name: :min_b}})
        |> limit(5)
        |> Query.normalize()

      assert extract_module_queries(Module29) == [expected_term]
    end

    test "extracts every relationship of the target when an include name is an argument" do
      terms = extract_module_queries(Module37)

      assert Enum.map(terms, &Map.keys(&1.include)) == [[:a], [:b], [:c]]
    end

    test "extracts every entity and relationship pair when both are arguments" do
      terms = extract_module_queries(Module39)

      assert Enum.map(terms, &{&1.entity, Map.keys(&1.include)}) == [{Entity13, [:parent]}]
    end

    test "drops a candidate a later stage cannot satisfy rather than failing the build" do
      # Entity18 declares title and no relationships, so it survives the filter and has nothing for
      # the include to travel over - which used to fail the whole build rather than drop it.
      assert %{entity: Entity18} = filter(Entity18, title: "x")

      terms = extract_module_queries(Module39)

      assert Enum.map(terms, & &1.entity) == [Entity13]
    end

    test "extracts every entity type admitting a query whose entity is an argument" do
      terms = extract_module_queries(Module36)

      assert Enum.map(terms, & &1.entity) == [Entity2, Entity4]
    end

    test "extracts only the relationships a sub-builder admits" do
      terms = extract_module_queries(Module38)

      assert Enum.map(terms, &Map.keys(&1.include)) == [[:a]]
    end

    test "extracts one entity type when only one admits the query" do
      expected_term =
        Entity4
        |> filter(d: 1)
        |> Query.normalize()

      assert extract_module_queries(Module34) == [expected_term]
    end

    test "extracts a guarded capture ignoring the guard" do
      expected_term =
        Entity2
        |> filter(b: {:>=, %Placeholder{name: :min_b}})
        |> Query.normalize()

      assert extract_module_queries(Module10) == [expected_term]
    end

    test "extracts a placeholder as a membership list element" do
      expected_term =
        Entity2
        |> filter(b: [%Placeholder{name: :min_b}, 1])
        |> Query.normalize()

      assert extract_module_queries(Module26) == [expected_term]
    end

    test "extracts a placeholder from a call on an argument" do
      expected_term =
        Entity2
        |> filter(c: %Placeholder{name: :search})
        |> Query.normalize()

      assert extract_module_queries(Module13) == [expected_term]
    end

    test "extracts a placeholder from arithmetic on an argument" do
      expected_term =
        Entity2
        |> filter(b: %Placeholder{name: :n})
        |> Query.normalize()

      assert extract_module_queries(Module32) == [expected_term]
    end

    test "extracts a placeholder from a call whose argument nests it in a map" do
      expected_term =
        Entity2
        |> filter(b: %Placeholder{name: :n})
        |> Query.normalize()

      assert extract_module_queries(Module33) == [expected_term]
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
        |> include(:a, fn sub -> filter(sub, b: {:>=, %Placeholder{name: :min_b}}) end)
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
        |> filter(b: {:>=, %Placeholder{name: :min_b}})
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

    test "extracts placeholders from a local parameterized capture through its shim" do
      expected_term =
        Entity2
        |> filter(b: {:>=, %Placeholder{name: :min_b}})
        |> Query.normalize()

      assert extract_module_queries(Module2) == [expected_term]
    end

    test "extracts placeholders from a remote parameterized capture in argument order" do
      expected_term =
        Entity2
        |> filter(b: {:>=, %Placeholder{name: :min_b}}, c: %Placeholder{name: :search})
        |> Query.normalize()

      assert extract_module_queries(Module6) == [expected_term]
    end

    test "extracts placeholders from an inline from_query function" do
      expected_term =
        Entity2
        |> filter(b: {:>=, %Placeholder{name: :min_b}})
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
        |> filter(b: {:>=, %Placeholder{name: :min_b}})
        |> Query.normalize()

      assert extract_module_queries(Module18) == [nil_clause_term, bound_clause_term]
    end

    test "extracts through a local helper" do
      expected_term =
        Entity2
        |> filter(b: {:>=, %Placeholder{name: :min_b}})
        |> Query.normalize()

      assert extract_module_queries(Module14) == [expected_term]
    end

    test "extracts through variable binds and concrete native calls" do
      expected_term =
        Entity2
        |> filter(a: true)
        |> filter(b: {:>=, %Placeholder{name: :min_b}}, c: "ABC")
        |> Query.normalize()

      assert extract_module_queries(Module15) == [expected_term]
    end

    test "forks a case on a placeholder into per-clause variants" do
      any_clause_term = Query.normalize(Entity2)

      other_clause_term =
        Entity2
        |> filter(c: %Placeholder{name: :status})
        |> Query.normalize()

      assert extract_module_queries(Module17) == [any_clause_term, other_clause_term]
    end

    test "forks a cond into per-clause variants" do
      bound_clause_term =
        Entity2
        |> filter(b: {:>=, %Placeholder{name: :min_b}})
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
        |> filter(b: {:>=, %Placeholder{name: :min_b}})
        |> Query.normalize()

      assert extract_module_queries(Module11) == [else_branch_term, then_branch_term]
    end

    test "yields no terms for modules without prop declarations" do
      assert extract_module_queries(Entity2) == []
    end

    test "raises naming every function the refusal was reached through" do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_43.ex:22: query capture for prop :entities in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module43 builds an invalid query - unknown attribute :nonexistent in Hologram.Test.Fixtures.Entity.Module2 - known attributes: :a, :b, :c, :created_at, :id, :updated_at

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_43.ex:22: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module43.narrow/1
            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_43.ex:18: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module43.entities_query/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_module_queries(Module43)
      end
    end

    test "raises on a call to an undefined function" do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_24.ex:20: query capture for prop :entities in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module24 calls undefined function Hologram.Test.Fixtures.Compiler.QueryExtractor.Module19.missing_helper/1

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_24.ex:20: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module24.entities_query/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_module_queries(Module24)
      end
    end

    test "raises on an include name argument the target has no relationship for" do
      expected_msg =
        "test/elixir/support/fixtures/compiler/query_extractor/module_40.ex:17: query capture for prop :entities in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module40 includes a relationship of Hologram.Test.Fixtures.Entity.Module4, which declares none - a prop with no window would read rows nothing ever fills"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_module_queries(Module40)
      end
    end

    test "raises on a concrete field read off a value that is not a map" do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_42.ex:20: query capture for prop :entities in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module42 reads field :limit off 5, which is not a map

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_42.ex:20: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module42.entities_query/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_module_queries(Module42)
      end
    end

    test "raises on a concrete field read the value has no field for" do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_41.ex:20: query capture for prop :entities in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module41 reads field :mising off a value that has no such field - known fields: :limit

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_41.ex:20: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module41.entities_query/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_module_queries(Module41)
      end
    end

    test "raises on a capture no entity type admits" do
      expected_msg =
        "test/elixir/support/fixtures/compiler/query_extractor/module_35.ex:17: query capture for prop :entities in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module35 builds no query that any entity type of the build admits - it filters on :no_entity_declares_this - a prop with no window would read rows nothing ever fills"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_module_queries(Module35)
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
        "test/elixir/support/fixtures/compiler/query_extractor/module_8.ex:15: query capture for prop :entities in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module8 destructures an argument - arguments must be plain names, each binding to the like-named component assign"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_module_queries(Module8)
      end
    end

    test "raises on a non-capture from_query value" do
      expected_msg =
        "test/elixir/support/fixtures/compiler/query_extractor/module_3.ex: from_query for prop :entities in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module3 must be a function capture, got: 123"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_module_queries(Module3)
      end
    end

    test "raises on a query capture argument named vars" do
      expected_msg =
        "test/elixir/support/fixtures/compiler/query_extractor/module_7.ex:15: query capture for prop :entities in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module7 names an argument vars - the name is reserved, name arguments after the component assigns they bind to"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_module_queries(Module7)
      end
    end

    test "raises on helpers that call each other in a circle" do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_44.ex:23: query capture for prop :entities in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module44 recursively calls Hologram.Test.Fixtures.Compiler.QueryExtractor.Module44.narrow/1 - recursive helpers are not extractable

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_44.ex:23: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module44.widen/1
            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_44.ex:21: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module44.narrow/1
            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_44.ex:18: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module44.entities_query/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_module_queries(Module44)
      end
    end

    test "raises on a recursive helper" do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_21.ex:16: query capture for prop :entities in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module21 recursively calls Hologram.Test.Fixtures.Compiler.QueryExtractor.Module21.entities_query/1 - recursive helpers are not extractable

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_21.ex:16: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module21.entities_query/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_module_queries(Module21)
      end
    end

    test "raises on an argument the build cannot enumerate" do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_30.ex:17: query capture for prop :entities in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module30 passes an argument to filter/2 in a position the build cannot enumerate - the rows to download cannot be worked out without its value

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_30.ex:17: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module30.entities_query/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_module_queries(Module30)
      end
    end

    test "raises on an invalid query built by a capture" do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_31.ex:18: query capture for prop :entities in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module31 builds an invalid query - unknown attribute :nonexistent in Hologram.Test.Fixtures.Entity.Module2 - known attributes: :a, :b, :c, :created_at, :id, :updated_at

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_31.ex:18: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module31.entities_query/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_module_queries(Module31)
      end
    end

    test "raises on branching inside an anonymous sub-builder" do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_22.ex:17: query capture for prop :entities in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module22 branches inside an anonymous function - not extractable yet

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_22.ex:17: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module22.entities_query/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_module_queries(Module22)
      end
    end
  end

  describe "extract_prop_params/1" do
    test "names an argument the builder reads a field from" do
      assert extract_prop_params(Module27) == [entities: [:entity]]
    end

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
        "test/elixir/support/fixtures/component/module_25.ex:18: query capture for prop :entities in Hologram.Test.Fixtures.Component.Module25 names argument 1 differently across its clauses (:min_b, :max_b) - one argument position binds one prop, and which prop it is has to be known before any clause is chosen, so every clause must name it alike. Rename them to the prop this argument binds, leave the position a literal or an underscored name in the clauses that do not use it, or bind through an adapter naming it once: from_query: fn min_b -> your_query(min_b) end"

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
        "test/elixir/support/fixtures/component/module_11.ex: from_query for prop :entities in Hologram.Test.Fixtures.Component.Module11 binds argument :min_b - no like-named prop is declared"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_slot_bindings!(Component11)
      end
    end

    # A shared builder's argument names are a cross-module contract - each consumer is validated
    # against its own declared slots.
    test "raises when a remote capture argument binds no declared prop" do
      expected_msg =
        "test/elixir/support/fixtures/component/module_14.ex: from_query for prop :entities in Hologram.Test.Fixtures.Component.Module14 binds argument :min_b - no like-named prop is declared"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_slot_bindings!(Component14)
      end
    end

    # Slots are what a component is GIVEN. A query's answer is not that, and binding one would
    # make a query depend on another query with nothing ordering the two - the injector runs them
    # in declaration order, so the same pair resolves or raises by which was written first.
    test "raises when a capture argument binds a from_query prop of the same component" do
      expected_msg =
        "test/elixir/support/fixtures/component/module_27.ex: from_query for prop :derived in Hologram.Test.Fixtures.Component.Module27 binds argument :entities, which is a from_query prop of the same component - a query argument binds a value the component is GIVEN, never one another query produced"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_slot_bindings!(Component27)
      end
    end

    test "raises when an argument position is named by no clause" do
      expected_msg =
        "test/elixir/support/fixtures/component/module_23.ex: from_query capture for prop :entities in Hologram.Test.Fixtures.Component.Module23 has an argument position no clause names - it cannot bind a prop"

      assert_error Hologram.CompileError, expected_msg, fn ->
        validate_slot_bindings!(Component23)
      end
    end
  end
end
