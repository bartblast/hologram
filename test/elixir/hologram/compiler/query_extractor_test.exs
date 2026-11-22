defmodule Hologram.Compiler.QueryExtractorTest do
  use Hologram.Test.BasicCase, async: true
  use Hologram.DB

  import Hologram.Compiler.QueryExtractor

  alias Hologram.Commons.PLT
  alias Hologram.Query
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module142
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module146
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module53
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module54
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module55
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module64
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module74
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module75
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module76
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module77
  alias Hologram.Test.Fixtures.Entity.Module33, as: Entity33
  alias Hologram.Test.Fixtures.Entity.Module36, as: Entity36
  alias Hologram.Test.Fixtures.Entity.Module43, as: Entity43

  # A frame opens with the application it came from, which carries the framework's version - the
  # one part of an expected message that cannot be spelled out and stay true across a release.
  @app "(hologram #{Application.spec(:hologram, :vsn)})"

  # Started once for the file: the IR PLT the walks read, which fills as they ask for modules.
  setup_all do
    [ir_plt: PLT.start()]
  end

  defp source_line(path, needle) do
    path
    |> File.read!()
    |> String.split("\n")
    |> Enum.find_index(&String.contains?(&1, needle))
    |> Kernel.+(1)
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

    test "follows a query builder assigning a stage to the wildcard", %{ir_plt: ir_plt} do
      {definition, _read_modules} = derived_definition(Module142, :wildcard_bound, ir_plt)

      assert definition ==
               {:query,
                %Query{
                  cardinality: :count,
                  entity: Entity33,
                  source: {Entity36, [:channel, :messages]}
                }}
    end

    test "refuses a call of an undefined function on values the build knows", %{ir_plt: ir_plt} do
      fixture = "test/elixir/support/fixtures/compiler/query_extractor/module_141.ex"
      line = source_line(fixture, "wrap_term(String).not_a_function(1)")

      expected_msg =
        normalize_newlines("""
        #{fixture}:#{line}: derived field :undefined_native in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module142 calls undefined function String.not_a_function/1

            #{@app} #{fixture}:#{line}: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module141.undefined_native/1
            #{@app} lib/my_app/member.ex:55: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module142.__derived_definition__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derived_definition(Module142, :undefined_native, ir_plt)
      end
    end

    test "refuses a call on a value that is no module", %{ir_plt: ir_plt} do
      assert_raise Hologram.CompileError,
                   ~r/derived field :not_a_module_target in .+ calls not_a_function\/1 on "x", which is not a module/,
                   fn -> derived_definition(Module142, :not_a_module_target, ir_plt) end
    end

    # The function the builder calls exists, so what it raises is its own.
    test "leaves alone an undefined function a defined function calls", %{ir_plt: ir_plt} do
      assert_raise UndefinedFunctionError, ~r/String\.not_a_function\/1/, fn ->
        derived_definition(Module142, :undefined_inside_native, ir_plt)
      end
    end

    # Nothing binds the value, but the code still runs it.
    test "refuses an invalid stage assigned to the wildcard", %{ir_plt: ir_plt} do
      assert_raise Hologram.CompileError,
                   ~r/derived field :wildcard_invalid in .+ builds an invalid query - unknown attribute :nonexistent/,
                   fn -> derived_definition(Module142, :wildcard_invalid, ir_plt) end
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
        test/elixir/support/fixtures/compiler/query_extractor/module_53.ex:27: derived field :looping in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module54 recursively calls Hologram.Test.Fixtures.Compiler.QueryExtractor.Module53.looping/1 - recursive helpers can't be resolved at build time

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_53.ex:27: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module53.looping/1
            #{@app} lib/my_app/member.ex:23: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module54.__derived_definition__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derived_definition(Module54, :looping, ir_plt)
      end
    end

    # The row decides which key the map holds, so the build can't tell whether the guard holds.
    test "refuses a guard reading a map keyed by a field of the row", %{ir_plt: ir_plt} do
      assert_raise Hologram.CompileError,
                   ~r/derived field :keyed_by_field in .+ branches on a field of the row/,
                   fn -> derived_definition(Module142, :keyed_by_field, ir_plt) end
    end

    # The field is nil on some rows, and on those it's the key read.
    test "refuses a read of a map keyed by a field of the row", %{ir_plt: ir_plt} do
      assert_raise Hologram.CompileError,
                   ~r/derived field :keyed_read in .+ reads nil off a map keyed by a field of the row/,
                   fn -> derived_definition(Module142, :keyed_read, ir_plt) end
    end

    test "refuses a function reading a field of the row handed to a call the build runs", %{
      ir_plt: ir_plt
    } do
      fixture = "test/elixir/support/fixtures/compiler/query_extractor/module_145.ex"
      line = source_line(fixture, "Enum.uniq_by(fn x -> if x == 1, do: first")

      assert_raise Hologram.CompileError,
                   ~r/#{fixture}:#{line}: derived field :closure_reading_fields in .+ passes a field of the row to Enum\.uniq_by\/2/,
                   fn -> derived_definition(Module146, :closure_reading_fields, ir_plt) end
    end

    # Two functions holding equal values are equal, so the count depends on the row.
    test "refuses functions holding fields of the row compared by a call the build runs", %{
      ir_plt: ir_plt
    } do
      assert_raise Hologram.CompileError,
                   ~r/derived field :closures_compared in .+ passes a field of the row to Enum\.uniq\/1/,
                   fn -> derived_definition(Module146, :closures_compared, ir_plt) end
    end

    test "refuses a function naming a field of the row on a path it doesn't take", %{
      ir_plt: ir_plt
    } do
      assert_raise Hologram.CompileError,
                   ~r/derived field :field_on_path_not_taken in .+ passes a field of the row to Enum\.map\/2/,
                   fn -> derived_definition(Module146, :field_on_path_not_taken, ir_plt) end
    end

    test "refuses a function returning a field of the row it made itself", %{ir_plt: ir_plt} do
      assert_raise Hologram.CompileError,
                   ~r/derived field :closure_making_field in .+ returns a field of the row from a function handed to another call/,
                   fn -> derived_definition(Module146, :closure_making_field, ir_plt) end
    end

    # The inner functions capture nothing, so they're equal, whatever x the outer one was given.
    test "keeps only what a function names, so equal functions compare equal", %{ir_plt: ir_plt} do
      {{:query, query}, _read_modules} =
        derived_definition(Module146, :closures_from_one_fn, ir_plt)

      assert query.take == 1
    end

    test "reads a value holding an improper list", %{ir_plt: ir_plt} do
      {{:query, query}, _read_modules} = derived_definition(Module146, :improper_list, ir_plt)

      assert query.take == 1
    end

    test "refuses a branch on strings joined from fields of the row", %{ir_plt: ir_plt} do
      assert_raise Hologram.CompileError,
                   ~r/derived field :computed_joined in .+ passes a field of the row to :erlang\.==\/2/,
                   fn -> derived_definition(Module146, :computed_joined, ir_plt) end
    end

    test "refuses a branch on a value a condition on the row picks", %{ir_plt: ir_plt} do
      assert_raise Hologram.CompileError,
                   ~r/derived field :computed_picked in .+ passes a field of the row to :erlang\.==\/2/,
                   fn -> derived_definition(Module146, :computed_picked, ir_plt) end
    end

    test "refuses a branch on whether a condition on the row holds", %{ir_plt: ir_plt} do
      assert_raise Hologram.CompileError,
                   ~r/derived field :computed_condition in .+ branches on a field of the row/,
                   fn -> derived_definition(Module146, :computed_condition, ir_plt) end
    end

    # The picked key can be the one read, so the value depends on the row.
    test "refuses a read of a map keyed by a value a condition on the row picks", %{
      ir_plt: ir_plt
    } do
      assert_raise Hologram.CompileError,
                   ~r/derived field :computed_key in .+ reads :limit off a map keyed by a field of the row/,
                   fn -> derived_definition(Module146, :computed_key, ir_plt) end
    end

    test "decides an anonymous function's guard on its argument", %{ir_plt: ir_plt} do
      {{:query, query}, _read_modules} = derived_definition(Module146, :guard_held, ir_plt)

      assert query.take == 5

      assert_raise Hologram.CompileError,
                   ~r/derived field :guard_on_argument in .+ calls an anonymous function with 1, which no clause matches - the code raises FunctionClauseError there/,
                   fn -> derived_definition(Module146, :guard_on_argument, ir_plt) end
    end

    test "decides an anonymous function's guard on a value from outside it", %{ir_plt: ir_plt} do
      {{:query, query}, _read_modules} =
        derived_definition(Module146, :guard_on_outer_value_held, ir_plt)

      assert query.take == 5

      assert_raise Hologram.CompileError,
                   ~r/derived field :guard_on_outer_value in .+ calls an anonymous function with 1, which no clause matches/,
                   fn -> derived_definition(Module146, :guard_on_outer_value, ir_plt) end
    end

    test "decides an anonymous function's literal parameter", %{
      ir_plt: ir_plt
    } do
      {{:query, query}, _read_modules} =
        derived_definition(Module146, :literal_param_matched, ir_plt)

      assert query.take == 5

      assert_raise Hologram.CompileError,
                   ~r/derived field :literal_param in .+ calls an anonymous function with 2, which no clause matches/,
                   fn -> derived_definition(Module146, :literal_param, ir_plt) end
    end

    test "decides an anonymous function's repeated parameter", %{
      ir_plt: ir_plt
    } do
      {{:query, query}, _read_modules} =
        derived_definition(Module146, :repeated_param_equal, ir_plt)

      assert query.take == 5

      assert_raise Hologram.CompileError,
                   ~r/derived field :repeated_param in .+ calls an anonymous function with 1, 2, which no clause matches/,
                   fn -> derived_definition(Module146, :repeated_param, ir_plt) end
    end

    test "keeps the last value of equal map keys when the literal key is last", %{
      ir_plt: ir_plt
    } do
      {{:query, query}, _read_modules} =
        derived_definition(Module146, :map_equal_keys_literal_last, ir_plt)

      assert query.take == 3
    end

    test "keeps the last value of equal map keys when the variable key is last", %{
      ir_plt: ir_plt
    } do
      {{:query, query}, _read_modules} =
        derived_definition(Module146, :map_equal_keys_variable_last, ir_plt)

      assert query.take == 3
    end

    test "takes the case clause a known value matches", %{ir_plt: ir_plt} do
      {definition, _read_modules} = derived_definition(Module142, :by_case, ir_plt)

      assert definition ==
               {:query,
                %Query{
                  entity: Entity33,
                  sort: [position: :asc, id: :asc],
                  source: {Entity36, [:channel, :messages]},
                  take: 2
                }}
    end

    test "takes the first cond clause whose condition holds for a known value", %{ir_plt: ir_plt} do
      {definition, _read_modules} = derived_definition(Module142, :cond_sized, ir_plt)

      assert definition ==
               {:query,
                %Query{
                  entity: Entity33,
                  sort: [position: :asc, id: :asc],
                  source: {Entity36, [:channel, :messages]},
                  take: 3
                }}
    end

    test "takes the branch of an if on a known value", %{ir_plt: ir_plt} do
      {definition, _read_modules} = derived_definition(Module142, :if_strict, ir_plt)

      assert definition ==
               {:query,
                %Query{
                  entity: Entity33,
                  sort: [position: :asc, id: :asc],
                  source: {Entity36, [:channel, :messages]},
                  take: 1
                }}
    end

    test "takes the clause whose guard holds for a known value", %{ir_plt: ir_plt} do
      {definition, _read_modules} = derived_definition(Module142, :bounded_large, ir_plt)

      assert definition ==
               {:query,
                %Query{
                  entity: Entity33,
                  sort: [position: :asc, id: :asc],
                  source: {Entity36, [:channel, :messages]},
                  take: 10
                }}
    end

    test "takes the clause after one whose guard fails for a known value", %{ir_plt: ir_plt} do
      {definition, _read_modules} = derived_definition(Module142, :bounded_small, ir_plt)

      assert definition ==
               {:query,
                %Query{
                  entity: Entity33,
                  sort: [position: :asc, id: :asc],
                  source: {Entity36, [:channel, :messages]},
                  take: 5
                }}
    end

    test "takes the clause after one whose guard raises for a known value", %{ir_plt: ir_plt} do
      # length/1 raises on an atom, and a guard that raises doesn't hold, as in Elixir.
      {definition, _read_modules} = derived_definition(Module142, :listed, ir_plt)

      assert definition ==
               {:query,
                %Query{
                  entity: Entity33,
                  sort: [position: :asc, id: :asc],
                  source: {Entity36, [:channel, :messages]}
                }}
    end

    test "takes the clause whose guards joined by and hold for known values", %{ir_plt: ir_plt} do
      {definition, _read_modules} = derived_definition(Module142, :windowed, ir_plt)

      assert definition ==
               {:query,
                %Query{
                  entity: Entity33,
                  sort: [position: :asc, id: :asc],
                  source: {Entity36, [:channel, :messages]},
                  take: 5
                }}
    end

    test "takes the clause whose guard joined by or holds on its right side", %{ir_plt: ir_plt} do
      {definition, _read_modules} = derived_definition(Module142, :either, ir_plt)

      assert definition ==
               {:query,
                %Query{
                  entity: Entity33,
                  sort: [position: :asc, id: :asc],
                  source: {Entity36, [:channel, :messages]},
                  take: 1
                }}
    end

    test "takes the clause after one naming a variable twice for two different values", %{
      ir_plt: ir_plt
    } do
      {definition, _read_modules} = derived_definition(Module142, :same, ir_plt)

      assert definition ==
               {:query,
                %Query{
                  entity: Entity33,
                  sort: [position: :asc, id: :asc],
                  source: {Entity36, [:channel, :messages]},
                  take: 2
                }}
    end

    test "raises on a case no clause of which matches a known value", %{ir_plt: ir_plt} do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_141.ex:18: derived field :case_unmatched in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module142 reaches a case on :closed, which no clause matches - the code raises CaseClauseError there

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_141.ex:18: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module141.by_case/2
            #{@app} lib/my_app/member.ex:15: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module142.__derived_definition__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derived_definition(Module142, :case_unmatched, ir_plt)
      end
    end

    test "raises on a cond none of whose conditions holds for a known value", %{ir_plt: ir_plt} do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_141.ex:79: derived field :cond_unmatched in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module142 reaches a cond none of whose conditions holds - the code raises CondClauseError there

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_141.ex:79: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module141.strictly_sized/2
            #{@app} lib/my_app/member.ex:21: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module142.__derived_definition__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derived_definition(Module142, :cond_unmatched, ir_plt)
      end
    end

    test "raises on a known value no clause of a function matches", %{ir_plt: ir_plt} do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_141.ex:24: derived field :kind_unmatched in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module142 calls Hologram.Test.Fixtures.Compiler.QueryExtractor.Module141.of_kind/2 with %Hologram.Query{entity: Hologram.Test.Fixtures.Entity.Module33, source: {Hologram.Test.Fixtures.Entity.Module36, [:channel, :messages]}}, :closed, which no clause matches - the code raises FunctionClauseError there

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_141.ex:24: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module141.by_kind/2
            #{@app} lib/my_app/member.ex:33: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module142.__derived_definition__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derived_definition(Module142, :kind_unmatched, ir_plt)
      end
    end

    test "raises on a call to an undefined function", %{ir_plt: ir_plt} do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_141.ex:90: derived field :undefined in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module142 calls undefined function Hologram.Test.Fixtures.Compiler.QueryExtractor.Module55.missing_helper/1

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_141.ex:90: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module141.undefined/1
            #{@app} lib/my_app/member.ex:47: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module142.__derived_definition__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derived_definition(Module142, :undefined, ir_plt)
      end
    end

    test "raises on a field read off a known value that is not a map", %{ir_plt: ir_plt} do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_141.ex:42: derived field :not_a_map in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module142 reads field :limit off 5, which is not a map

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_141.ex:42: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module141.limited/2
            #{@app} lib/my_app/member.ex:41: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module142.__derived_definition__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derived_definition(Module142, :not_a_map, ir_plt)
      end
    end

    test "raises on a field read off a known map that has no such field", %{ir_plt: ir_plt} do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_141.ex:54: derived field :no_such_field in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module142 reads field :lmit off a value that has no such field - known fields: :limit

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_141.ex:54: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module141.misspelled/2
            #{@app} lib/my_app/member.ex:39: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module142.__derived_definition__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derived_definition(Module142, :no_such_field, ir_plt)
      end
    end

    test "raises on a query builder building an invalid query", %{ir_plt: ir_plt} do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_141.ex:40: derived field :invalid in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module142 builds an invalid query - unknown attribute :nonexistent in Hologram.Test.Fixtures.Entity.Module33 - known attributes: :body, :channel_id, :channel_name, :created_at, :id, :later_count, :position, :server_created_at, :server_updated_at, :tier, :updated_at

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_141.ex:40: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module141.invalid/1
            #{@app} lib/my_app/member.ex:31: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module142.__derived_definition__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derived_definition(Module142, :invalid, ir_plt)
      end
    end

    test "raises on an anonymous function of arity 4", %{ir_plt: ir_plt} do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_141.ex:35: derived field :four_ary in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module142 uses an anonymous function of arity 4 - only arities 1-3 can be resolved at build time yet

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_141.ex:35: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module141.four_ary/1
            #{@app} lib/my_app/member.ex:27: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module142.__derived_definition__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derived_definition(Module142, :four_ary, ir_plt)
      end
    end

    test "raises on a call to a function whose head destructures a parameter", %{ir_plt: ir_plt} do
      expected_msg =
        normalize_newlines("""
        lib/my_app/member.ex:23: derived field :destructured in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module142 calls a function whose head destructures a parameter - only plain names, literals, and _ can be resolved at build time yet

            #{@app} lib/my_app/member.ex:23: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module142.__derived_definition__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derived_definition(Module142, :destructured, ir_plt)
      end
    end

    test "raises on a composite case pattern", %{ir_plt: ir_plt} do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_141.ex:84: derived field :composite in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module142 uses a composite case pattern - only variables, literals, and _ can be resolved at build time yet

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_141.ex:84: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module141.tagged/2
            #{@app} lib/my_app/member.ex:17: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module142.__derived_definition__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derived_definition(Module142, :composite, ir_plt)
      end
    end

    test "raises on a pattern match in a query builder's body", %{ir_plt: ir_plt} do
      expected_msg =
        ~r/^test\/elixir\/support\/fixtures\/compiler\/query_extractor\/module_141\.ex:49: derived field :body_match in Hologram\.Test\.Fixtures\.Compiler\.QueryExtractor\.Module142 pattern-matches in its body - only plain variable binds can be resolved at build time yet\n/

      assert_error Hologram.CompileError, expected_msg, fn ->
        derived_definition(Module142, :body_match, ir_plt)
      end
    end

    test "raises on a query builder outside the project", %{ir_plt: ir_plt} do
      expected_msg =
        normalize_newlines("""
        lib/my_app/member.ex:43: derived field :outside in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module142 calls Function.identity/1, which the build cannot follow - a query builder is a module of the project

            #{@app} lib/my_app/member.ex:43: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module142.__derived_definition__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derived_definition(Module142, :outside, ir_plt)
      end
    end

    test "raises on a path read off a set a stage narrowed", %{ir_plt: ir_plt} do
      expected_msg =
        normalize_newlines("""
        test/elixir/support/fixtures/compiler/query_extractor/module_141.ex:26: derived field :narrowed in Hologram.Test.Fixtures.Compiler.QueryExtractor.Module142 reads channel off a set its stages narrowed - a path goes through relationships, before any stage reads the set

            #{@app} test/elixir/support/fixtures/compiler/query_extractor/module_141.ex:26: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module141.channel_of/1
            #{@app} lib/my_app/member.ex:37: Hologram.Test.Fixtures.Compiler.QueryExtractor.Module142.__derived_definition__/1\
        """)

      assert_error Hologram.CompileError, expected_msg, fn ->
        derived_definition(Module142, :narrowed, ir_plt)
      end
    end
  end
end
