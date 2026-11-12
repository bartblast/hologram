defmodule Hologram.Compiler.QueryExtractorTest do
  use Hologram.Test.BasicCase, async: true
  use Hologram.DB

  import Hologram.Compiler.QueryExtractor

  alias Hologram.Commons.PLT
  alias Hologram.Compiler.IR
  alias Hologram.Query
  alias Hologram.Query.Placeholder
  alias Hologram.Query.Stage
  alias Hologram.Reflection
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module100
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module101
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module102
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module103
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module104
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module105
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module106
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module107
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module108
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module109
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module110
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module111
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module112
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module113
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module114
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module115
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module116
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module117
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module118
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module119
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module120
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module121
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module122
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module123
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module124
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module125
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module126
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module127
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module128
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module130
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module131
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module132
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module53
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module54
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module55
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module64
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module74
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module75
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module76
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module77
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module78
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module80
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module81
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module82
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module83
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module85
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module86
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module87
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module88
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module89
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module90
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module91
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module92
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module93
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module94
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module95
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module96
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module97
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module99
  alias Hologram.Test.Fixtures.Component.Module1, as: Component1
  alias Hologram.Test.Fixtures.Entity.Module13, as: Entity13
  alias Hologram.Test.Fixtures.Entity.Module18, as: Entity18
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2
  alias Hologram.Test.Fixtures.Entity.Module26, as: Entity26
  alias Hologram.Test.Fixtures.Entity.Module3, as: Entity3
  alias Hologram.Test.Fixtures.Entity.Module33, as: Entity33
  alias Hologram.Test.Fixtures.Entity.Module36, as: Entity36
  alias Hologram.Test.Fixtures.Entity.Module4, as: Entity4
  alias Hologram.Test.Fixtures.Entity.Module43, as: Entity43
  alias Hologram.Test.Fixtures.Entity.Module5, as: Entity5

  # A frame opens with the application it came from, which carries the framework's version - the
  # one part of an expected message that cannot be spelled out and stay true across a release.
  @app "(hologram #{Application.spec(:hologram, :vsn)})"

  # Listed once for the file: the candidate set a placeholder in an entity position is replayed over,
  # and the IR PLT the extractions read, which fills as they ask for modules.
  setup_all do
    [entity_types: Reflection.list_entities(), ir_plt: PLT.start()]
  end

  describe "derived_definition/3" do
    test "follows a query builder called as the whole body", %{ir_plt: ir_plt} do
      {definition, read_modules} = derived_definition(Entity36, :unread_count, ir_plt)

      assert definition ==
               {:query,
                %Query{
                  cardinality: :count,
                  entity: Entity33,
                  filter: [{:created_at, :>, {:attribute, {:outer, 1, :last_read_at}}}],
                  source: {Entity36, [:channel, :messages]}
                }}

      assert read_modules == [Module53]
    end

    test "follows a query builder piped into a stage", %{ir_plt: ir_plt} do
      {definition, read_modules} = derived_definition(Entity36, :recent_unread, ir_plt)

      assert definition ==
               {:query,
                %Query{
                  entity: Entity33,
                  filter: [{:created_at, :>, {:attribute, {:outer, 1, :last_read_at}}}],
                  sort: [position: :asc, id: :asc],
                  source: {Entity36, [:channel, :messages]},
                  take: 5
                }}

      assert read_modules == [Module53]
    end

    test "follows the query builders a query builder calls", %{ir_plt: ir_plt} do
      {definition, read_modules} = derived_definition(Entity36, :unread_through_helper, ir_plt)

      assert definition ==
               {:query,
                %Query{
                  entity: Entity33,
                  filter: [{:created_at, :>, {:attribute, {:outer, 1, :last_read_at}}}],
                  sort: [position: :asc, id: :asc],
                  source: {Entity36, [:channel, :messages]}
                }}

      assert read_modules == [Module53, Module55]
    end

    test "reports a module whose function a query builder runs", %{ir_plt: ir_plt} do
      {definition, read_modules} = derived_definition(Module76, :capped, ir_plt)

      assert definition ==
               {:query,
                %Query{
                  entity: Entity33,
                  sort: [position: :asc, id: :asc],
                  source: {Entity36, [:channel, :messages]},
                  take: 2
                }}

      assert read_modules == [Module74, Module75]
    end

    test "reports a module whose function a closure inside a query builder runs", %{
      ir_plt: ir_plt
    } do
      {_definition, read_modules} = derived_definition(Module76, :capped_in_closure, ir_plt)

      assert read_modules == [Module74, Module75]
    end

    test "reads a chain of related rows two hops deep inside a query builder", %{ir_plt: ir_plt} do
      {definition, read_modules} = derived_definition(Entity36, :member_messages, ir_plt)

      assert definition ==
               {:query,
                %Query{
                  entity: Entity33,
                  sort: [position: :asc, id: :asc],
                  source: {Entity36, [:member, :channel, :messages]}
                }}

      assert read_modules == [Module53]
    end

    test "takes the clause of a query builder a known argument matches", %{ir_plt: ir_plt} do
      {definition, read_modules} = derived_definition(Module54, :forked, ir_plt)

      assert definition ==
               {:query,
                %Query{
                  entity: Entity33,
                  sort: [position: :asc, id: :asc],
                  source: {Entity36, [:channel, :messages]},
                  take: 2
                }}

      assert read_modules == [Module53]
    end

    test "follows a query builder of the entity type's own", %{ir_plt: ir_plt} do
      {definition, read_modules} = derived_definition(Entity43, :recent, ir_plt)

      assert definition ==
               {:query,
                %Query{
                  entity: Entity33,
                  sort: [position: :asc, id: :asc],
                  source: {Entity43, [:channel, :messages]},
                  take: 2
                }}

      assert read_modules == [Entity43]
    end

    test "follows a private query builder of the entity type's own", %{ir_plt: ir_plt} do
      {definition, read_modules} = derived_definition(Entity43, :unread, ir_plt)

      assert definition ==
               {:query,
                %Query{
                  entity: Entity33,
                  filter: [{:created_at, :>, {:attribute, {:outer, 1, :last_read_at}}}],
                  sort: [position: :asc, id: :asc],
                  source: {Entity43, [:channel, :messages]}
                }}

      assert read_modules == [Entity43]
    end

    test "follows a query builder of the entity type's own piped into a stage", %{
      ir_plt: ir_plt
    } do
      {definition, read_modules} = derived_definition(Entity43, :piped_recent, ir_plt)

      assert definition ==
               {:query,
                %Query{
                  entity: Entity33,
                  sort: [position: :asc, id: :asc],
                  source: {Entity43, [:channel, :messages]},
                  take: 1
                }}

      assert read_modules == [Entity43]
    end

    test "raises on a query builder of the entity type's own returning a value", %{
      ir_plt: ir_plt
    } do
      expected_msg =
        normalize_newlines("""
        lib/my_app/member.ex:7: derived field :counted in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module77 calls Hologram.Test.Fixtures.Compiler.QueryExtractor.Module77.message_total/1, which returns 3 - a builder builds a query, and a value computed from fields is written in the derived field's own body

            #{@app} lib/my_app/member.ex:7: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module77.__derived_definition__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derived_definition(Module77, :counted, ir_plt)
      end
    end

    test "raises on a query builder of the entity type's own reading every row of a type", %{
      ir_plt: ir_plt
    } do
      expected_msg =
        normalize_newlines("""
        lib/my_app/member.ex:9: derived field :every_message in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module77 builds an invalid definition - a derived field's query starts from a relationship of the row, got a query of every Hologram.Test.Fixtures.Entity.Module33 - read the rows through an argument naming the relationship

            #{@app} lib/my_app/member.ex:9: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module77.__derived_definition__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derived_definition(Module77, :every_message, ir_plt)
      end
    end

    test "raises on a query builder guard reading a field of the row", %{ir_plt: ir_plt} do
      expected_msg =
        normalize_newlines("""
        lib/my_app/member.ex:7: derived field :guarded in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module64 branches on a field of the row - a derived field's definition is one query, built before any row is read

            #{@app} lib/my_app/member.ex:7: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module64.__derived_definition__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derived_definition(Module64, :guarded, ir_plt)
      end
    end

    test "raises on a branch on a field of the row", %{ir_plt: ir_plt} do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_53.ex:10: derived field :branched in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module54 branches on a field of the row - a derived field's definition is one query, built before any row is read

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_53.ex:10: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module53.by_flag/2
            #{@app} lib/my_app/member.ex:7: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module54.__derived_definition__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derived_definition(Module54, :branched, ir_plt)
      end
    end

    test "raises on a query builder clause chosen by a field of the row", %{ir_plt: ir_plt} do
      expected_msg =
        normalize_newlines("""
        lib/my_app/member.ex:15: derived field :dispatched in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module54 branches on a field of the row - a derived field's definition is one query, built before any row is read

            #{@app} lib/my_app/member.ex:15: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module54.__derived_definition__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derived_definition(Module54, :dispatched, ir_plt)
      end
    end

    test "raises on a field of the row passed to Elixir", %{ir_plt: ir_plt} do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_53.ex:17: derived field :capitalized in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module54 passes a field of the row to String.capitalize/1 - a field of the row reaches query stages and query builders only

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_53.ex:17: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module53.capitalized/1
            #{@app} lib/my_app/member.ex:9: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module54.__derived_definition__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derived_definition(Module54, :capitalized, ir_plt)
      end
    end

    test "raises on a query builder returning a value", %{ir_plt: ir_plt} do
      expected_msg =
        normalize_newlines("""
        lib/my_app/member.ex:13: derived field :counted in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module54 calls Hologram.Test.Fixtures.Compiler.QueryExtractor.Module53.message_total/1, which returns 3 - a builder builds a query, and a value computed from fields is written in the derived field's own body

            #{@app} lib/my_app/member.ex:13: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module54.__derived_definition__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derived_definition(Module54, :counted, ir_plt)
      end
    end

    test "raises on a query builder given no field returning a value", %{ir_plt: ir_plt} do
      expected_msg =
        normalize_newlines("""
        lib/my_app/member.ex:11: derived field :constant in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module54 calls Hologram.Test.Fixtures.Compiler.QueryExtractor.Module53.constant/0, which returns 5 - a builder builds a query, and a value computed from fields is written in the derived field's own body

            #{@app} lib/my_app/member.ex:11: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module54.__derived_definition__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derived_definition(Module54, :constant, ir_plt)
      end
    end

    test "raises on a dot on a field of the row holding a value", %{ir_plt: ir_plt} do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_53.ex:25: derived field :dotted in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module54 reads length off the :nickname field of the row, which holds a value - a path goes through relationships

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_53.ex:25: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module53.length_of/1
            #{@app} lib/my_app/member.ex:17: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module54.__derived_definition__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derived_definition(Module54, :dotted, ir_plt)
      end
    end

    test "raises on a path a related row does not declare", %{ir_plt: ir_plt} do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_53.ex:33: derived field :missing in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module54 builds an invalid definition - member.nothing names :nothing, which is not a field of Hologram.Test.Fixtures.Entity.Module34

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_53.ex:33: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module53.missing/1
            #{@app} lib/my_app/member.ex:25: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module54.__derived_definition__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derived_definition(Module54, :missing, ir_plt)
      end
    end

    test "raises on a path through a set to one row", %{ir_plt: ir_plt} do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_53.ex:39: derived field :senders in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module54 builds an invalid definition - channel.messages.channel reads through a set to one value per row of it - a derived field reads a set's rows with a query, or one value of the row through to-one relationships

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_53.ex:39: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module53.senders/1
            #{@app} lib/my_app/member.ex:27: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module54.__derived_definition__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derived_definition(Module54, :senders, ir_plt)
      end
    end

    test "raises on a recursive query builder", %{ir_plt: ir_plt} do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_53.ex:27: derived field :looping in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module54 recursively calls Hologram.Test.Fixtures.Compiler.QueryExtractor.Module53.looping/1 - recursive helpers are not extractable

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_53.ex:27: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module53.looping/1
            #{@app} lib/my_app/member.ex:23: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module54.__derived_definition__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derived_definition(Module54, :looping, ir_plt)
      end
    end
  end

  describe "extract_derived_queries/3" do
    setup %{entity_types: entity_types, ir_plt: ir_plt} do
      queries =
        Module78
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      %{queries: queries}
    end

    test "registers a query reading an argument with a placeholder for it", %{queries: queries} do
      assert queries.by_wanted == [
               %Query{
                 entity: Entity2,
                 filter: [{:a, :==, {:placeholder, :wanted}}],
                 sort: [id: :asc]
               }
             ]
    end

    test "registers a query reading no argument", %{queries: queries} do
      assert queries.ripe == [
               %Query{entity: Entity2, filter: [{:a, :==, true}], sort: [id: :asc]}
             ]
    end

    test "registers an entity type as a query of every row", %{queries: queries} do
      assert queries.every_row == [%Query{entity: Entity2, sort: [id: :asc]}]
    end

    test "registers the query a builder of another module builds", %{queries: queries} do
      assert queries.through_builder == [
               %Query{
                 entity: Entity2,
                 filter: [{:a, :==, {:placeholder, :wanted}}],
                 sort: [id: :asc]
               }
             ]
    end

    test "registers a query for each branch on an argument", %{queries: queries} do
      assert queries.ripe_or_all == [
               %Query{entity: Entity2, sort: [id: :asc]},
               %Query{entity: Entity2, filter: [{:a, :==, true}], sort: [id: :asc]}
             ]
    end

    test "registers an entity type a branch returns", %{queries: queries} do
      assert queries.branch_entity == [%Query{entity: Entity2, sort: [id: :asc]}]
    end

    test "keeps only the replay the field's type names of a query over an entity type an argument holds",
         %{queries: queries} do
      assert queries.sorted_entity == [%Query{entity: Entity2, sort: [id: :asc]}]
    end

    test "registers nothing for a field computing a plain value", %{queries: queries} do
      refute Map.has_key?(queries, :labels)
    end

    test "registers nothing for a field calling a function of Hologram's own", %{
      queries: queries
    } do
      refute Map.has_key?(queries, :can_read)
    end

    test "registers nothing for a field passing on an entity type a function returns", %{
      queries: queries
    } do
      refute Map.has_key?(queries, :entity_label)
    end

    test "registers an entity type a variable bound to it returns", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module131
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      assert queries.bound_entity == [%Query{entity: Entity2, sort: [id: :asc]}]
    end

    test "registers an entity type a variable bound to a function's result returns", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module131
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      assert queries.bound_helper_entity == [%Query{entity: Entity2, sort: [id: :asc]}]
    end

    test "registers an entity type a variable bound through another match returns", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module131
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      assert queries.chained_bound_entity == [%Query{entity: Entity2, sort: [id: :asc]}]
    end

    test "registers an entity type a helper returns through a variable", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module131
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      assert queries.helper_bound_entity == [%Query{entity: Entity2, sort: [id: :asc]}]
    end

    test "registers an entity type a match the field ends with returns", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module131
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      assert queries.tail_bound_entity == [%Query{entity: Entity2, sort: [id: :asc]}]
    end

    test "registers nothing for a field passing on an entity type a variable holds", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module131
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      refute Map.has_key?(queries, :bound_entity_label)
    end

    test "registers nothing for a field returning an entity a stage changed an attribute of", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module132
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      refute Map.has_key?(queries, :edited)
    end

    test "registers nothing for a field returning an entity a stage changed a counter of", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module132
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      refute Map.has_key?(queries, :bumped)
    end

    test "registers nothing for a field returning an entity it trusts", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module132
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      refute Map.has_key?(queries, :trusted_row)
    end

    test "registers an entity type the field trusts as a query of every row", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module132
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      assert queries.trusted_entity_type == [
               %Query{entity: Entity2, sort: [id: :asc], trust: true}
             ]
    end

    test "doesn't run a field computing a plain value", %{queries: queries} do
      refute Map.has_key?(queries, :raising)
    end

    test "registers a query whose function ignores the field an underscored argument reads", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      assert extract_derived_queries(Module130, entity_types, ir_plt) == [
               entities: [%Query{entity: Entity2, filter: [{:a, :==, true}], sort: [id: :asc]}]
             ]
    end

    test "registers nothing for a module declaring no derived field", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      assert extract_derived_queries(Component1, entity_types, ir_plt) == []
    end

    test "raises on a field building a query that returns a value on a branch", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      expected_msg =
        "test/elixir/support/fixtures/compiler/query_extractor/module_80.ex:10: derived field :ripe_or_three in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module80 builds a query, but returns 3 - a derived field holding rows returns the query, and a value computed from the rows is a derived field of its own"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module80, entity_types, ir_plt)
      end
    end

    test "raises on a query of a set where a count is declared", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      expected_msg =
        "test/elixir/support/fixtures/compiler/query_extractor/module_81.ex:8: derived field :total in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module81 is declared :integer, but its query is a set of Hologram.Test.Fixtures.Entity.Module2 rows"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module81, entity_types, ir_plt)
      end
    end

    test "raises on a query of a set where one row is declared", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      expected_msg =
        "test/elixir/support/fixtures/compiler/query_extractor/module_83.ex:8: derived field :first in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module83 is declared Hologram.Test.Fixtures.Entity.Module2, but its query is a set of Hologram.Test.Fixtures.Entity.Module2 rows"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module83, entity_types, ir_plt)
      end
    end

    test "raises on a query of a count where a set is declared", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      expected_msg =
        "test/elixir/support/fixtures/compiler/query_extractor/module_86.ex:8: derived field :rows in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module86 is declared [Hologram.Test.Fixtures.Entity.Module2], but its query is a count of Hologram.Test.Fixtures.Entity.Module2 rows"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module86, entity_types, ir_plt)
      end
    end

    test "raises on a query of one row where a set is declared", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      expected_msg =
        "test/elixir/support/fixtures/compiler/query_extractor/module_87.ex:8: derived field :rows in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module87 is declared [Hologram.Test.Fixtures.Entity.Module2], but its query is one Hologram.Test.Fixtures.Entity.Module2 row"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module87, entity_types, ir_plt)
      end
    end

    test "raises on a query over an entity type an argument holds that is never the declared type",
         %{entity_types: entity_types, ir_plt: ir_plt} do
      expected_msg =
        "test/elixir/support/fixtures/compiler/query_extractor/module_88.ex:10: derived field :titled in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module88 is declared [Hologram.Test.Fixtures.Entity.Module2], but its query, over the entity type entity_type holds, is never a set of Hologram.Test.Fixtures.Entity.Module2 rows"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module88, entity_types, ir_plt)
      end
    end

    test "raises on a query no entity type admits", %{entity_types: entity_types, ir_plt: ir_plt} do
      expected_msg =
        "test/elixir/support/fixtures/compiler/query_extractor/module_89.ex:11: derived field :unknown in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module89 builds no query that any entity type of the build admits - it filters on :no_entity_declares_this - a derived field with no window would read rows nothing ever fills"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module89, entity_types, ir_plt)
      end
    end

    test "raises on a query over a field read off another derived field's row", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_85.ex:10: derived field :narrowed in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module85 runs a query over derived field :first's rows - a query reads an entity type, so filter the rows in Elixir or build the query from the same inputs

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_85.ex:10: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module85.__derived_narrowed__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module85, entity_types, ir_plt)
      end
    end

    test "raises on a query over another derived field's rows", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_82.ex:10: derived field :ripe_rows in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module82 runs a query over derived field :rows's rows - a query reads an entity type, so filter the rows in Elixir or build the query from the same inputs

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_82.ex:10: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module82.__derived_ripe_rows__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module82, entity_types, ir_plt)
      end
    end

    test "raises on a query an Erlang function fails on", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_90.ex:13: derived field :ripe_total in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module90 uses a query as a value - a query describes rows, so declare it as a derived field and read that

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_90.ex:13: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module90.__derived_ripe_total__/0\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module90, entity_types, ir_plt)
      end
    end

    test "raises on a query an Elixir function fails on", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_91.ex:11: derived field :ripe_total in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module91 uses a query as a value - a query describes rows, so declare it as a derived field and read that

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_91.ex:11: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module91.__derived_ripe_total__/0\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module91, entity_types, ir_plt)
      end
    end

    test "raises on a query a function of the project interpolates into a string", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_92.ex:12: derived field :label in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module92 uses a query as a value - a query describes rows, so declare it as a derived field and read that

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_92.ex:12: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module92.__derived_label__/0\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module92, entity_types, ir_plt)
      end
    end

    test "raises on a query returned inside a tuple", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_93.ex:8: derived field :pair in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module93 uses a query as a value - a query describes rows, so declare it as a derived field and read that

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_93.ex:8: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module93.__derived_pair__/0\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module93, entity_types, ir_plt)
      end
    end

    test "raises on a query bound to a variable and dropped", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_94.ex:9: derived field :rows in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module94 uses a query as a value - a query describes rows, so declare it as a derived field and read that

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_94.ex:9: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module94.__derived_rows__/0\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module94, entity_types, ir_plt)
      end
    end

    test "raises on a dropped chain of stages", %{entity_types: entity_types, ir_plt: ir_plt} do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_95.ex:11: derived field :rows in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module95 uses a query as a value - a query describes rows, so declare it as a derived field and read that

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_95.ex:11: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module95.__derived_rows__/0\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module95, entity_types, ir_plt)
      end
    end

    test "raises on a query built in a closure and dropped", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_96.ex:9: derived field :rows in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module96 uses a query as a value - a query describes rows, so declare it as a derived field and read that

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_96.ex:9: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module96.__derived_rows__/0\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module96, entity_types, ir_plt)
      end
    end

    test "raises on a query whose rows an Elixir function iterates", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_99.ex:11: derived field :labels in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module99 uses a query as a value - a query describes rows, so declare it as a derived field and read that

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_99.ex:11: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module99.__derived_labels__/0\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module99, entity_types, ir_plt)
      end
    end

    test "raises on a query a function of the project returns inside a tuple", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      expected_msg =
        "test/elixir/support/fixtures/compiler/query_extractor/module_100.ex:8: derived field :pair in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module100 uses a query as a value - a query describes rows, so declare it as a derived field and read that"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module100, entity_types, ir_plt)
      end
    end

    test "raises on a query a followed function of the project drops", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_98.ex:18: derived field :rows in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module101 uses a query as a value - a query describes rows, so declare it as a derived field and read that

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_98.ex:18: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module98.drop_ripe/1
            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_101.ex:11: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module101.__derived_rows__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module101, entity_types, ir_plt)
      end
    end

    test "raises on a query an Elixir function given an argument takes, as a value only known at runtime",
         %{entity_types: entity_types, ir_plt: ir_plt} do
      expected_msg =
        "test/elixir/support/fixtures/compiler/query_extractor/module_102.ex:10: derived field :rows in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module102 builds a query, but returns a value only known at runtime - a derived field holding rows returns the query, and a value computed from the rows is a derived field of its own"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module102, entity_types, ir_plt)
      end
    end

    test "registers a query a function of the project the walk runs builds on", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module97
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      assert queries.applied == [
               %Query{entity: Entity2, filter: [{:a, :==, true}], sort: [c: :asc, id: :asc]}
             ]
    end

    test "registers a query a function of the project takes inside its options", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module97
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      assert queries.from_options == [
               %Query{entity: Entity2, filter: [{:a, :==, true}], sort: [c: :asc, id: :asc]}
             ]
    end

    test "registers a query an Elixir function checks without failing", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module97
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      assert queries.checked == [
               %Query{entity: Entity2, filter: [{:a, :==, true}], sort: [id: :asc]}
             ]
    end

    test "registers each of the queries an argument chooses between", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module97
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      assert queries.chosen == [
               %Query{entity: Entity2, sort: [c: :asc, id: :asc]},
               %Query{entity: Entity2, filter: [{:a, :==, true}], sort: [id: :asc]}
             ]
    end

    test "registers a query that a builder of the project is given and returns", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module97
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      assert queries.kept == [
               %Query{entity: Entity2, filter: [{:a, :==, true}], sort: [id: :asc]}
             ]

      assert queries.kept_with_argument == [
               %Query{
                 entity: Entity2,
                 filter: [{:a, :==, {:placeholder, :wanted}}],
                 sort: [id: :asc]
               }
             ]
    end

    test "registers a query an Elixir function's closure builds on", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module97
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      assert queries.reduced == [
               %Query{entity: Entity2, filter: [{:a, :==, true}], sort: [c: :asc, id: :asc]}
             ]
    end

    test "registers a string interpolation the build knows as the string", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module97
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      assert queries.interpolated_known == [
               %Query{entity: Entity2, filter: [{:c, :==, "ripe pear"}], sort: [id: :asc]}
             ]
    end

    test "registers a string interpolating an argument with a placeholder for it", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module97
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      assert queries.interpolated == [
               %Query{
                 entity: Entity2,
                 filter: [{:c, :==, {:placeholder, :suffix}}],
                 sort: [id: :asc]
               }
             ]
    end

    test "builds the IR of a module the PLT lacks into it", %{entity_types: entity_types} do
      ir_plt = PLT.start()

      extract_derived_queries(Module107, entity_types, ir_plt)

      assert PLT.member?(ir_plt, Module107)
    end

    # The PLT holds Module108's IR under Module107's key, so the term tells which IR was read: both
    # fields are ripe, Module107's filters on a, Module108's on b.
    test "reads the IR the PLT holds instead of building it", %{entity_types: entity_types} do
      ir_plt = PLT.put(PLT.start(), Module107, IR.for_module(Module108))

      expected_term =
        Entity2
        |> filter(b: 1)
        |> Stage.normalize()

      assert extract_derived_queries(Module107, entity_types, ir_plt) == [ripe: [expected_term]]
    end

    test "registers a placeholder for a nested field read off an argument", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module103
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      expected_term =
        Entity2
        |> filter(c: ^%Placeholder{name: :"related.b.c"})
        |> Stage.normalize()

      assert queries.by_nested_field == [expected_term]
    end

    test "registers a placeholder for a field read off an argument", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module103
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      expected_term =
        Entity2
        |> filter(b: ^%Placeholder{name: :"row.b"})
        |> Stage.normalize()

      assert queries.by_row_field == [expected_term]
    end

    test "registers a field read on a concrete map", %{entity_types: entity_types, ir_plt: ir_plt} do
      queries =
        Module103
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      expected_term =
        Entity2
        |> filter(b >= ^%Placeholder{name: :min_b})
        |> take(5)
        |> Stage.normalize()

      assert queries.bounded_by_map == [expected_term]
    end

    test "registers a placeholder inside a quantifier's condition", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module103
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      expected_term =
        Entity26
        |> filter(any(message <- messages, message.body == ^%Placeholder{name: :body}))
        |> Stage.normalize()

      assert expected_term.filter == [
               {:any, {[:messages], [{:body, :==, {:placeholder, :body}}]}}
             ]

      assert queries.quantified == [expected_term]
    end

    test "registers a placeholder as a membership list element", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module103
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      expected_term =
        Entity2
        |> filter(b in [^%Placeholder{name: :min_b}, 1])
        |> Stage.normalize()

      assert queries.in_list == [expected_term]
    end

    test "registers a placeholder for a call on an argument", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module103
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      expected_term =
        Entity2
        |> filter(c: ^%Placeholder{name: :search})
        |> Stage.normalize()

      assert queries.by_search == [expected_term]
    end

    test "registers a placeholder for arithmetic on an argument", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module103
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      expected_term =
        Entity2
        |> filter(b: ^%Placeholder{name: :n})
        |> Stage.normalize()

      assert queries.doubled == [expected_term]
    end

    test "registers a placeholder for a call whose argument nests it in a map", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module103
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      expected_term =
        Entity2
        |> filter(b: ^%Placeholder{name: :n})
        |> Stage.normalize()

      assert queries.through_map == [expected_term]
    end

    test "registers the query a capture of another module's function builds", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module103
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      expected_term =
        Entity2
        |> filter(b: 123)
        |> Stage.normalize()

      assert queries.cross_module == [expected_term]
    end

    test "registers the branch a function reading no argument takes on known values", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module103
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      expected_term =
        Entity2
        |> filter(b >= 100)
        |> Stage.normalize()

      assert queries.known_branch == [expected_term]
    end

    test "registers a query an anonymous function builds", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module103
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      expected_term =
        Entity3
        |> include(a)
        |> filter(created_at >= ^%Placeholder{name: :since})
        |> Stage.normalize()

      assert queries.through_anonymous == [expected_term]
    end

    test "registers an include through a path beside an argument", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module103
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      expected_term =
        Entity5
        |> include(a.a)
        |> filter(created_at >= ^%Placeholder{name: :since})
        |> Stage.normalize()

      assert queries.included_path == [expected_term]
    end

    test "registers a placeholder for a stage called on the stage module", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module103
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      expected_term =
        Entity2
        |> filter(b >= ^%Placeholder{name: :min_b})
        |> Stage.normalize()

      assert queries.on_stage_module == [expected_term]
    end

    test "registers the query a local helper builds", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module103
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      expected_term =
        Entity2
        |> filter(b >= ^%Placeholder{name: :min_b})
        |> Stage.normalize()

      assert queries.through_local == [expected_term]
    end

    test "registers a query built through variable binds and concrete native calls", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module103
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      expected_term =
        Entity2
        |> filter(a: true)
        |> filter(b >= ^%Placeholder{name: :min_b} and c == "ABC")
        |> Stage.normalize()

      assert queries.through_binds == [expected_term]
    end

    test "registers a query for each clause of a case on an argument", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module104
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      any_clause_term = Stage.normalize(Entity2)

      other_clause_term =
        Entity2
        |> filter(c: ^%Placeholder{name: :status})
        |> Stage.normalize()

      assert queries.by_status == [any_clause_term, other_clause_term]
    end

    test "registers a query for each clause of a cond on an argument", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module104
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      bound_clause_term =
        Entity2
        |> filter(b >= ^%Placeholder{name: :min_b})
        |> Stage.normalize()

      fallback_clause_term =
        Entity2
        |> filter(a: true)
        |> Stage.normalize()

      assert queries.cond_bound == [bound_clause_term, fallback_clause_term]
    end

    test "registers a query for each branch of an if on an argument", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module104
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      else_branch_term =
        Entity2
        |> filter(a: true)
        |> Stage.normalize()

      then_branch_term =
        Entity2
        |> filter(b >= ^%Placeholder{name: :min_b})
        |> Stage.normalize()

      assert queries.if_bound == [else_branch_term, then_branch_term]
    end

    test "registers a query for each clause of another module's helper an argument reaches", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module104
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      nil_clause_term =
        Entity2
        |> filter(a: true)
        |> Stage.normalize()

      bound_clause_term =
        Entity2
        |> filter(b >= ^%Placeholder{name: :min_b})
        |> Stage.normalize()

      assert queries.helper_clauses == [nil_clause_term, bound_clause_term]
    end

    test "registers a query for each clause an argument leaves undecided, past the ones a known argument rules out",
         %{entity_types: entity_types, ir_plt: ir_plt} do
      queries =
        Module104
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      nil_clause_term =
        Entity2
        |> filter(a: true)
        |> Stage.normalize()

      bound_clause_term =
        Entity2
        |> filter(b >= ^%Placeholder{name: :min_b})
        |> Stage.normalize()

      assert queries.mixed == [nil_clause_term, bound_clause_term]
    end

    test "prunes the variants forks combine and no run takes", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module104
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      first_term =
        Entity2
        |> filter(b >= ^%Placeholder{name: :min_b})
        |> take(10)
        |> Stage.normalize()

      second_term =
        Entity2
        |> filter(b >= ^%Placeholder{name: :min_b})
        |> take(1)
        |> Stage.normalize()

      assert queries.paired == [first_term, second_term]
    end

    test "registers a query for each clause of a guard reading an argument", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module104
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      capped_term =
        Entity2
        |> filter(b >= ^%Placeholder{name: :min_b})
        |> take(10)
        |> Stage.normalize()

      limited_term =
        Entity2
        |> filter(b >= ^%Placeholder{name: :min_b})
        |> take(^%Placeholder{name: :limit})
        |> Stage.normalize()

      assert queries.guard_limit == [capped_term, limited_term]
    end

    test "registers the clause a known argument matches, past the ones it does not", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module105
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      assert queries.all_kinds == [Stage.normalize(Entity2)]
    end

    test "registers the clause after one whose guard fails for a known argument", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module105
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      expected_term =
        Entity2
        |> filter(b >= ^%Placeholder{name: :min_b})
        |> take(5)
        |> Stage.normalize()

      assert queries.bounded_small == [expected_term]
    end

    test "registers the branch of an if on a known value", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module105
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      expected_term =
        Entity2
        |> filter(b >= ^%Placeholder{name: :min_b})
        |> Stage.normalize()

      assert queries.strict == [expected_term]
    end

    test "registers the first clause of a cond whose condition holds for a known value", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module105
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      expected_term =
        Entity2
        |> filter(b >= ^%Placeholder{name: :min_b})
        |> take(3)
        |> Stage.normalize()

      assert queries.sized == [expected_term]
    end

    test "registers the clause whose guard holds for a known argument", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module105
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      expected_term =
        Entity2
        |> filter(b >= ^%Placeholder{name: :min_b})
        |> take(10)
        |> Stage.normalize()

      assert queries.bounded_large == [expected_term]
    end

    test "registers the clause whose guards joined by and hold for known arguments", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module105
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      expected_term =
        Entity2
        |> filter(b >= ^%Placeholder{name: :min_b})
        |> take(5)
        |> Stage.normalize()

      assert queries.windowed == [expected_term]
    end

    test "registers the clause after one whose guard raises for a known argument", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module105
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      expected_term =
        Entity2
        |> filter(b >= ^%Placeholder{name: :min_b})
        |> Stage.normalize()

      assert queries.listed == [expected_term]
    end

    test "registers the branch on a known value inside an anonymous function", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module105
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      expected_term =
        Entity2
        |> filter(b >= ^%Placeholder{name: :min_b})
        |> Stage.normalize()

      assert queries.inside_closure == [expected_term]
    end

    test "registers the clause a head naming one variable twice matches", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module105
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      expected_term =
        Entity2
        |> filter(b >= ^%Placeholder{name: :min_b})
        |> take(2)
        |> Stage.normalize()

      assert queries.same_twice == [expected_term]
    end

    test "registers every relationship of the entity type when an include name is an argument", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module106
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      assert Enum.map(queries.every_relationship, &Map.keys(&1.include)) == [[:a], [:b], [:c]]
    end

    test "registers every inverse of the entity type too when an include name is an argument", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module106
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      assert Enum.map(queries.every_inverse, &Map.keys(&1.include)) == [[:messages], [:topic]]
    end

    test "registers every entity type and relationship pair when both are arguments", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module106
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      assert Enum.map(queries.entity_and_relation, &{&1.entity, Map.keys(&1.include)}) == [
               {Entity13, [:parent]}
             ]
    end

    test "drops a candidate a later stage cannot satisfy rather than failing the build", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      # Entity18 declares title and no relationships, so it survives the filter and has nothing for
      # the include to travel over - which used to fail the whole build rather than drop it.
      assert %{entity: Entity18} = filter(Entity18, title: "x")

      queries =
        Module106
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      assert Enum.map(queries.entity_and_relation, & &1.entity) == [Entity13]
    end

    test "registers every entity type admitting a count whose entity type is an argument", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      queries =
        Module106
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      assert Enum.map(queries.admitting_count, & &1.entity) == [Entity2, Entity4]
    end

    test "registers one entity type when only one admits a count whose entity type is an argument",
         %{entity_types: entity_types, ir_plt: ir_plt} do
      queries =
        Module106
        |> extract_derived_queries(entity_types, ir_plt)
        |> Map.new()

      expected_term =
        Entity4
        |> filter(d: 1)
        |> count()
        |> Stage.normalize()

      assert queries.one_admitting_count == [expected_term]
    end

    test "raises naming every function the refusal was reached through", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_109.ex:22: derived field :rows in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module109 builds an invalid query - unknown attribute :nonexistent in Hologram.Test.Fixtures.Entity.Module2 - known attributes: :a, :b, :c, :created_at, :id, :updated_at

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_109.ex:22: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module109.narrow/1
            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_109.ex:13: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module109.__derived_rows__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module109, entity_types, ir_plt)
      end
    end

    test "raises on a call to an undefined function", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_110.ex:17: derived field :rows in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module110 calls undefined function Hologram.Test.Fixtures.Compiler.QueryExtractor.Module19.missing_helper/1

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_110.ex:17: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module110.__derived_rows__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module110, entity_types, ir_plt)
      end
    end

    test "raises on an undefined function of the project the build runs on a query it knows", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_126.ex:16: derived field :rows in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module126 calls undefined function Hologram.Test.Fixtures.Compiler.QueryExtractor.Module19.missing_helper/1

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_126.ex:16: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module126.__derived_rows__/0\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module126, entity_types, ir_plt)
      end
    end

    test "raises on a function of the project the build runs that no clause of matches for another argument",
         %{
           entity_types: entity_types,
           ir_plt: ir_plt
         } do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_127.ex:14: derived field :rows in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module127 calls Hologram.Test.Fixtures.Compiler.QueryExtractor.Module98.narrow/2 with %Hologram.Query{entity: Hologram.Test.Fixtures.Entity.Module2, sort: [c: :asc]}, :unknown, which no clause matches - the code raises FunctionClauseError there

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_127.ex:14: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module127.__derived_rows__/0\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module127, entity_types, ir_plt)
      end
    end

    test "raises on a function of the project the build runs whose guard refuses a query", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_128.ex:13: derived field :ripe_total in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module128 calls Hologram.Test.Fixtures.Compiler.QueryExtractor.Module98.total/1 with %Hologram.Query{entity: Hologram.Test.Fixtures.Entity.Module2, filter: [{:a, :==, true}]}, which no clause matches - the code raises FunctionClauseError there

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_128.ex:13: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module128.__derived_ripe_total__/0\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module128, entity_types, ir_plt)
      end
    end

    test "raises on an include name argument the entity type has no relationship for", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      expected_msg =
        "test/elixir/support/fixtures/compiler/query_extractor/module_111.ex:10: derived field :rows in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module111 includes a relationship of Hologram.Test.Fixtures.Entity.Module4, which declares none - a derived field with no window would read rows nothing ever fills"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module111, entity_types, ir_plt)
      end
    end

    test "raises on a concrete field read off a value that is not a map", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_112.ex:13: derived field :rows in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module112 reads field :limit off 5, which is not a map

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_112.ex:13: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module112.__derived_rows__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module112, entity_types, ir_plt)
      end
    end

    test "raises on a concrete field read the value has no field for", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_113.ex:13: derived field :rows in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module113 reads field :mising off a value that has no such field - known fields: :limit

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_113.ex:13: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module113.__derived_rows__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module113, entity_types, ir_plt)
      end
    end

    test "raises on a query no entity type admits, naming each attribute of a disjunction", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      expected_msg =
        "test/elixir/support/fixtures/compiler/query_extractor/module_114.ex:11: derived field :rows in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module114 builds no query that any entity type of the build admits - it filters on :no_entity_declares_this, :no_entity_declares_this_either - a derived field with no window would read rows nothing ever fills"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module114, entity_types, ir_plt)
      end
    end

    test "raises on a query no entity type admits, naming a path it filters on", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      expected_msg =
        "test/elixir/support/fixtures/compiler/query_extractor/module_115.ex:11: derived field :rows in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module115 builds no query that any entity type of the build admits - it filters on no_entity_declares_this.x - a derived field with no window would read rows nothing ever fills"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module115, entity_types, ir_plt)
      end
    end

    test "raises on a query no entity type admits, naming both attributes of a comparison", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      expected_msg =
        "test/elixir/support/fixtures/compiler/query_extractor/module_116.ex:11: derived field :rows in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module116 builds no query that any entity type of the build admits - it filters on :no_entity_declares_this, :no_entity_declares_this_either - a derived field with no window would read rows nothing ever fills"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module116, entity_types, ir_plt)
      end
    end

    test "raises on a query no entity type admits, naming each filtered attribute once", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      expected_msg =
        "test/elixir/support/fixtures/compiler/query_extractor/module_117.ex:11: derived field :rows in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module117 builds no query that any entity type of the build admits - it filters on :no_entity_declares_this - a derived field with no window would read rows nothing ever fills"

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module117, entity_types, ir_plt)
      end
    end

    test "raises on helpers that call each other in a circle", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_118.ex:23: derived field :rows in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module118 recursively calls Hologram.Test.Fixtures.Compiler.QueryExtractor.Module118.narrow/1 - recursive helpers are not extractable

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_118.ex:23: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module118.widen/1
            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_118.ex:21: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module118.narrow/1
            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_118.ex:13: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module118.__derived_rows__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module118, entity_types, ir_plt)
      end
    end

    test "raises on a recursive helper", %{entity_types: entity_types, ir_plt: ir_plt} do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_119.ex:21: derived field :rows in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module119 recursively calls Hologram.Test.Fixtures.Compiler.QueryExtractor.Module119.rows_query/1 - recursive helpers are not extractable

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_119.ex:21: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module119.rows_query/1
            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_119.ex:10: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module119.__derived_rows__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module119, entity_types, ir_plt)
      end
    end

    test "raises on an argument the build cannot enumerate", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_120.ex:10: derived field :rows in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module120 passes an argument to filter/2 in a position the build cannot enumerate - the rows to download cannot be worked out without its value

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_120.ex:10: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module120.__derived_rows__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module120, entity_types, ir_plt)
      end
    end

    test "raises on an invalid query", %{entity_types: entity_types, ir_plt: ir_plt} do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_121.ex:13: derived field :rows in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module121 builds an invalid query - unknown attribute :nonexistent in Hologram.Test.Fixtures.Entity.Module2 - known attributes: :a, :b, :c, :created_at, :id, :updated_at

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_121.ex:13: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module121.__derived_rows__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module121, entity_types, ir_plt)
      end
    end

    test "raises on branching on an argument inside an anonymous function", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_122.ex:12: derived field :rows in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module122 branches inside an anonymous function - not extractable yet

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_122.ex:12: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module122.__derived_rows__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module122, entity_types, ir_plt)
      end
    end

    test "raises on a case no clause of which matches a known value", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_56.ex:26: derived field :rows in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module123 reaches a case on :closed, which no clause matches - the code raises CaseClauseError there

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_56.ex:26: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module56.case_kind/2
            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_123.ex:15: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module123.__derived_rows__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module123, entity_types, ir_plt)
      end
    end

    test "raises on a cond none of whose conditions holds for known values", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_56.ex:92: derived field :rows in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module124 reaches a cond none of whose conditions holds - the code raises CondClauseError there

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_56.ex:92: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module56.strictly_sized/2
            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_124.ex:11: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module124.__derived_rows__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module124, entity_types, ir_plt)
      end
    end

    test "raises on a known argument no clause matches", %{
      entity_types: entity_types,
      ir_plt: ir_plt
    } do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_125.ex:15: derived field :rows in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module125 calls Hologram.Test.Fixtures.Compiler.QueryExtractor.Module56.by_kind/2 with :closed, min_b, which no clause matches - the code raises FunctionClauseError there

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_125.ex:15: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module125.__derived_rows__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        extract_derived_queries(Module125, entity_types, ir_plt)
      end
    end
  end
end
