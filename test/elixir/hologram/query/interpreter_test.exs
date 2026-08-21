defmodule Hologram.Query.InterpreterTest do
  use Hologram.Test.DatabaseCase, async: true
  use Hologram.Query

  import Hologram.DB.EntityOperations, only: [add_relationship: 4, create: 1]
  import Hologram.Query.Interpreter

  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.DB.QueryRunner
  alias Hologram.Entity
  alias Hologram.Entity.NotIncluded
  alias Hologram.Query
  alias Hologram.Query.Placeholder
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module10
  alias Hologram.Test.Fixtures.Entity.Module17
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module5

  @entity_types [Module1, Module10, Module17, Module2, Module3, Module5]

  @mapping Mapper.derive!(@entity_types)

  # The whole point of this module: the same term over the same rows, run by the database and by
  # the interpreter, agreeing. Every test goes through here and then asserts what came back, so
  # that two empty results never pass for agreement.
  defp agreed(query, opts \\ []) do
    term = Query.normalize(query)
    bindings = Keyword.get(opts, :bindings, %{})

    expected =
      if Keyword.has_key?(opts, :actor_user_id) do
        QueryRunner.run_policied(term, @mapping, opts[:actor_user_id], bindings)
      else
        QueryRunner.run(term, @mapping, bindings)
      end

    actual = run(term, database(), opts)

    assert actual == expected

    actual
  end

  # What the client holds, built from what the database holds - every row of every type keyed by
  # id, and every to-many pair, the way the browser files them.
  defp database do
    rows =
      Map.new(@entity_types, fn entity_type ->
        table =
          entity_type
          |> Query.normalize()
          |> QueryRunner.run(@mapping)
          |> Map.new(&{&1.id, &1})

        {entity_type, table}
      end)

    %{facts: Enum.reduce(@entity_types, %{}, &facts/2), rows: rows}
  end

  # The pairs as the join tables hold them - which is what the wire sends a client and what its
  # relationship facts keep, read here from the one place the database keeps them.
  defp facts(entity_type, acc) do
    entity_type
    |> Mapper.join_tables()
    |> Enum.reduce(acc, fn join_table, joined ->
      {:ok, result} =
        Connection.query(
          ~s(SELECT "source_id", "target_id" FROM "hologram_data".#{Mapper.quote_identifier(join_table.name)}),
          []
        )

      Enum.reduce(result.rows, joined, fn [source_id, target_id], pairs ->
        key = {entity_type, join_table.relationship, Codec.decode(source_id, :uuid)}

        Map.update(
          pairs,
          key,
          [Codec.decode(target_id, :uuid)],
          &[Codec.decode(target_id, :uuid) | &1]
        )
      end)
    end)
  end

  defp module_10(attributes) do
    Module10
    |> Entity.new(attributes)
    |> create()
  end

  defp module_17(attributes) do
    Module17
    |> Entity.new(attributes)
    |> create()
  end

  # Ids are time-ordered but not strictly so within a millisecond, and a query with no order of
  # its own falls back to them - so what a MATCHING test asserts is which rows came back, not
  # the order the tiebreaker happened to put them in.
  defp matched_names(rows) do
    rows
    |> names()
    |> Enum.sort()
  end

  defp module_2(title) do
    Module2
    |> Entity.new(a: true, c: title)
    |> create()
  end

  defp matched_titles(rows) do
    rows
    |> titles()
    |> Enum.sort()
  end

  defp matched_module_17_titles(rows) do
    rows
    |> module_17_titles()
    |> Enum.sort()
  end

  defp module_17_titles(rows), do: Enum.map(rows, & &1.title)

  defp names(rows), do: Enum.map(rows, & &1.username)

  defp titles(rows), do: Enum.map(rows, & &1.c)

  describe "run/3 - equality and membership" do
    setup do
      %{
        first: module_10(count: 1, priority: 1, username: "ada"),
        second: module_10(count: 2, priority: 3, username: "bob"),
        third: module_10(count: 3, username: "cleo")
      }
    end

    test "matches a value" do
      assert matched_names(agreed(filter(Module10, priority: 3))) == ["bob"]
    end

    # Nil is a value like any other here: an unset attribute is unequal to a set one, so a
    # negated equality names the rows that never had it either.
    test "matches what is unequal, missing values included" do
      assert matched_names(agreed(filter(Module10, priority: {:!=, 3}))) == ["ada", "cleo"]
    end

    test "matches an unset attribute" do
      assert matched_names(agreed(filter(Module10, priority: nil))) == ["cleo"]
    end

    test "matches what is set" do
      assert matched_names(agreed(filter(Module10, priority: {:!=, nil}))) == ["ada", "bob"]
    end

    test "matches membership in a list" do
      assert matched_names(agreed(filter(Module10, priority: {:in, [1, 3]}))) == ["ada", "bob"]
    end

    test "matches membership in a list naming an unset value" do
      assert matched_names(agreed(filter(Module10, priority: {:in, [nil, 3]}))) == ["bob", "cleo"]
    end

    # A list without nil leaves the rows that have no value at all outside it, so excluding the
    # list keeps them.
    test "matches exclusion from a list, missing values included" do
      assert matched_names(agreed(filter(Module10, priority: {:not_in, [1]}))) == ["bob", "cleo"]
    end

    test "matches exclusion from a list naming an unset value" do
      assert matched_names(agreed(filter(Module10, priority: {:not_in, [nil, 1]}))) == ["bob"]
    end

    test "matches every predicate of a filter and no fewer" do
      query = filter(Module10, count: {:>=, 2}, priority: {:!=, nil})

      assert names(agreed(query)) == ["bob"]
    end
  end

  describe "run/3 - ordering comparisons" do
    setup do
      %{
        first:
          module_10(
            count: 1,
            held_at: ~U[2026-03-01 10:00:00Z],
            rating: 1.5,
            released_on: ~D[2026-03-01],
            username: "ada"
          ),
        second:
          module_10(
            count: 5,
            held_at: ~U[2027-06-01 10:00:00Z],
            rating: 4.5,
            released_on: ~D[2027-06-01],
            username: "bob"
          ),
        third: module_10(count: 9, username: "cleo")
      }
    end

    test "matches values above a bound" do
      assert matched_names(agreed(filter(Module10, count: {:>, 1}))) == ["bob", "cleo"]
    end

    test "matches values at or above a bound" do
      assert matched_names(agreed(filter(Module10, count: {:>=, 5}))) == ["bob", "cleo"]
    end

    test "matches values below a bound" do
      assert matched_names(agreed(filter(Module10, count: {:<, 5}))) == ["ada"]
    end

    test "matches values at or below a bound" do
      assert matched_names(agreed(filter(Module10, count: {:<=, 5}))) == ["ada", "bob"]
    end

    test "compares floats" do
      assert matched_names(agreed(filter(Module10, rating: {:>, 2.0}))) == ["bob"]
    end

    test "compares dates" do
      assert matched_names(agreed(filter(Module10, released_on: {:>=, ~D[2027-01-01]}))) == [
               "bob"
             ]
    end

    test "compares datetimes" do
      query = filter(Module10, held_at: {:<, ~U[2027-01-01 00:00:00Z]})

      assert names(agreed(query)) == ["ada"]
    end

    test "matches a range as its two bounds" do
      assert matched_names(agreed(filter(Module10, count: 1..5))) == ["ada", "bob"]
    end

    # An ordering line has no place to put a value that is not there, so a comparison passes
    # over the rows that have none - unlike the equality family, which counts them.
    test "passes over an unset attribute, whichever way the comparison points" do
      assert matched_names(agreed(filter(Module10, rating: {:>, 0.0}))) == ["ada", "bob"]
      assert matched_names(agreed(filter(Module10, rating: {:<, 100.0}))) == ["ada", "bob"]
    end
  end

  # Every ordering asserted here is settled by the keys the query declares. Two rows that tie on
  # all of them fall to the id, and ids generated within one millisecond are not ordered among
  # themselves - so a test resting on that would pass or fail by the clock.
  describe "run/3 - ordering" do
    setup do
      %{
        first: module_10(count: 3, priority: 5, username: "bob"),
        second: module_10(count: 2, priority: 1, username: "ada"),
        third: module_10(count: 1, username: "cleo")
      }
    end

    test "orders by an attribute" do
      assert names(agreed(order_by(Module10, :count))) == ["cleo", "ada", "bob"]
    end

    test "orders by an attribute descending" do
      assert names(agreed(order_by(Module10, [{:count, :desc}]))) == ["bob", "ada", "cleo"]
    end

    # The rows tie on the first key, so the second decides between them.
    test "orders by each key in turn" do
      module_10(count: 7, priority: 5, username: "eve")
      module_10(count: 7, priority: 1, username: "dana")

      query =
        Module10
        |> filter(count: 7)
        |> order_by([:count, :priority])

      assert names(agreed(query)) == ["dana", "eve"]
    end

    # Ascending puts them last and descending puts them first, which is where the database puts
    # them - a page reading its own rows shows them where the server would have.
    test "places missing values last when ascending" do
      assert names(agreed(order_by(Module10, :priority))) == ["ada", "bob", "cleo"]
    end

    test "places missing values first when descending" do
      assert names(agreed(order_by(Module10, [{:priority, :desc}]))) == ["cleo", "bob", "ada"]
    end

    # Lowercase ASCII only: the sort key of such a value IS the value, so both tiers agree
    # without the companion column this environment's schema does not carry. What the key does
    # to case and diacritics is asserted below, against the interpreter alone.
    test "orders strings" do
      assert names(agreed(order_by(Module10, :username))) == ["ada", "bob", "cleo"]
    end
  end

  describe "run/3 - ordering strings by their sort keys" do
    # The database orders a string by a companion column holding exactly this derived value, so
    # what is asserted here is the same order it would produce for a schema that carries one -
    # this test environment's does not, which is why the interpreter answers alone.
    test "orders by the derived key rather than by the bytes" do
      module_10(count: 1, username: "Zoe")
      module_10(count: 2, username: "ada")
      module_10(count: 3, username: "Ödön")
      module_10(count: 4, username: "bob")

      term =
        Module10
        |> order_by(:username)
        |> Query.normalize()

      assert names(run(term, database())) == ["ada", "bob", "Ödön", "Zoe"]
    end
  end

  describe "run/3 - ordering enums" do
    setup do
      %{
        first: module_17(priority: :medium, title: "a"),
        second: module_17(priority: :high, title: "b"),
        third: module_17(priority: :low, title: "c"),
        fourth: module_17(title: "d")
      }
    end

    # Declared, alphabetical and reverse-alphabetical are three different sequences for these
    # values, so an order that matches the declared one matches it on purpose.
    test "orders by the declared position, not the label" do
      assert module_17_titles(agreed(order_by(Module17, :priority))) == ["c", "a", "b", "d"]
    end

    test "orders by the declared position descending" do
      query = order_by(Module17, [{:priority, :desc}])

      assert module_17_titles(agreed(query)) == ["d", "b", "a", "c"]
    end

    test "settles a tie on an enum by the next key" do
      module_17(priority: :medium, title: "e")
      module_17(priority: :medium, title: "f")

      query = order_by(Module17, [:priority, :title])

      assert module_17_titles(agreed(query)) == ["c", "a", "e", "f", "b", "d"]
    end
  end

  describe "run/3 - comparing enums" do
    setup do
      %{
        first: module_17(priority: :medium, title: "a"),
        second: module_17(priority: :high, title: "b"),
        third: module_17(priority: :low, title: "c"),
        fourth: module_17(title: "d")
      }
    end

    # Declared order, not label order: :high is the LAST declared value, so a label comparison
    # would drop it here and keep :low, which is what makes this discriminate.
    test "matches values at or after a declared value" do
      query = filter(Module17, priority: {:>=, :medium})

      assert matched_module_17_titles(agreed(query)) == ["a", "b"]
    end

    test "matches values before a declared value" do
      query = filter(Module17, priority: {:<, :medium})

      assert matched_module_17_titles(agreed(query)) == ["c"]
    end

    test "passes over an unset enum" do
      query = filter(Module17, priority: {:>=, :low})

      assert matched_module_17_titles(agreed(query)) == ["a", "b", "c"]
    end

    test "compares a declared value bound to a placeholder" do
      query = filter(Module17, priority: {:>=, %Placeholder{name: :min}})

      assert matched_module_17_titles(agreed(query, bindings: %{min: :medium})) == ["a", "b"]
    end

    # The database executor refuses the binding before it builds a statement, so an undeclared
    # label never reaches Postgres there - and the interpreter refuses it in the same words.
    test "refuses a placeholder bound to a value the enum does not declare, as the database does" do
      term =
        Module17
        |> filter(priority: {:>=, %Placeholder{name: :min}})
        |> Query.normalize()

      expected_msg =
        "invalid value :urgent for placeholder :min - expected one of [:low, :medium, :high]"

      assert_error ArgumentError, expected_msg, fn ->
        QueryRunner.run(term, @mapping, %{min: :urgent})
      end

      assert_error ArgumentError, expected_msg, fn ->
        run(term, database(), bindings: %{min: :urgent})
      end
    end
  end

  describe "run/3 - view bounds" do
    setup do
      %{
        first: module_10(count: 1, username: "ada"),
        second: module_10(count: 2, username: "bob"),
        third: module_10(count: 3, username: "cleo")
      }
    end

    test "takes at most the limit" do
      query =
        Module10
        |> order_by(:count)
        |> limit(2)

      assert names(agreed(query)) == ["ada", "bob"]
    end

    test "skips the offset" do
      query =
        Module10
        |> order_by(:count)
        |> offset(1)

      assert names(agreed(query)) == ["bob", "cleo"]
    end

    test "skips before it takes" do
      query =
        Module10
        |> order_by(:count)
        |> offset(1)
        |> limit(1)

      assert names(agreed(query)) == ["bob"]
    end
  end

  describe "run/3 - terminals" do
    setup do
      %{
        first: module_10(count: 1, priority: 1, username: "ada"),
        second: module_10(count: 2, priority: 3, username: "bob"),
        third: module_10(count: 3, username: "cleo")
      }
    end

    test "returns the first entity of a single-result query" do
      query =
        Module10
        |> order_by(:count)
        |> one()

      assert agreed(query).username == "ada"
    end

    test "returns nothing for a single-result query matching no entity" do
      query =
        Module10
        |> filter(count: 99)
        |> one()

      assert agreed(query) == nil
    end

    test "returns how many entities match" do
      query =
        Module10
        |> filter(priority: {:!=, nil})
        |> count()

      assert agreed(query) == 2
    end

    # A count counts what the query evaluates to, so a bounded query counts what its bounds
    # leave rather than what its filter matched.
    test "counts what the view bounds leave" do
      query =
        Module10
        |> limit(2)
        |> count()

      assert agreed(query) == 2
    end
  end

  describe "run/3 - placeholders" do
    setup do
      %{
        first: module_10(count: 1, priority: 1, username: "ada"),
        second: module_10(count: 2, priority: 3, username: "bob")
      }
    end

    test "matches against the value bound to a placeholder" do
      query = filter(Module10, priority: %Placeholder{name: :priority})

      assert matched_names(agreed(query, bindings: %{priority: 3})) == ["bob"]
    end

    test "matches against a list bound to a placeholder" do
      query = filter(Module10, priority: {:in, %Placeholder{name: :priorities}})

      assert matched_names(agreed(query, bindings: %{priorities: [1, 3]})) == ["ada", "bob"]
    end

    # Identity with the database covers what each REFUSES, not only what each answers - so a
    # binding the caller did not give is a caller error here too, rather than a filter nothing
    # passes. Each refusal is asserted of BOTH, which is the only way the messages are held
    # together.
    test "refuses a placeholder the bindings do not name, as the database does" do
      term =
        Module10
        |> filter(priority: %Placeholder{name: :priority})
        |> Query.normalize()

      expected_msg = "missing value for placeholder :priority"

      assert_error ArgumentError, expected_msg, fn ->
        QueryRunner.run(term, @mapping, %{})
      end

      assert_error ArgumentError, expected_msg, fn ->
        run(term, database(), bindings: %{})
      end
    end

    test "refuses a nil value bound to a placeholder, as the database does" do
      term =
        Module10
        |> filter(priority: %Placeholder{name: :priority})
        |> Query.normalize()

      expected_msg = "nil value for placeholder :priority - use an explicit nil predicate instead"

      assert_error ArgumentError, expected_msg, fn ->
        QueryRunner.run(term, @mapping, %{priority: nil})
      end

      assert_error ArgumentError, expected_msg, fn ->
        run(term, database(), bindings: %{priority: nil})
      end
    end

    # A literal list may name nil - it is part of a term rather than a value handed to one - so
    # the refusal is of the BINDING, not of the operator it feeds.
    test "refuses a nil element in a list bound to a placeholder, as the database does" do
      term =
        Module10
        |> filter(priority: {:in, %Placeholder{name: :priorities}})
        |> Query.normalize()

      expected_msg =
        "nil element in the list for placeholder :priorities - use an explicit nil predicate instead"

      assert_error ArgumentError, expected_msg, fn ->
        QueryRunner.run(term, @mapping, %{priorities: [nil, 3]})
      end

      assert_error ArgumentError, expected_msg, fn ->
        run(term, database(), bindings: %{priorities: [nil, 3]})
      end
    end
  end

  # Read policies are the server's business and the interpreter evaluates none of them, so the
  # type these run against is one anyone may read - what is being compared is the actor
  # predicate, and a narrowing policy would be the database answering a different question.
  describe "run/3 - the acting user" do
    setup do
      %{first: module_2("first"), second: module_2("second")}
    end

    test "matches against who is asking", %{second: second} do
      query = filter(Module2, id: {:actor})

      assert titles(agreed(query, actor_user_id: second.id)) == ["second"]
    end

    test "matches everything but who is asking", %{first: first} do
      query = filter(Module2, id: {:!=, {:actor}})

      assert titles(agreed(query, actor_user_id: first.id)) == ["second"]
    end

    # There is nobody to compare against, so nothing answers - the same silence the database
    # gives a statement asking about an actor that is not there.
    test "matches nothing for a visitor" do
      query = filter(Module2, id: {:actor})

      assert agreed(query, actor_user_id: nil) == []
    end

    # The negated form is where that silence has to be deliberate: nobody is UNEQUAL to every
    # row, so a predicate left to compare against nothing would answer with everything.
    test "matches nothing for a visitor, whichever way the predicate points" do
      query = filter(Module2, id: {:!=, {:actor}})

      assert agreed(query, actor_user_id: nil) == []
    end
  end

  describe "run/3 - includes" do
    setup do
      required =
        Module1
        |> Entity.new()
        |> create()

      target = module_2("the to-one target")

      source =
        Module3
        |> Entity.new(b_id: target.id, c_id: required.id)
        |> create()

      %{required: required, source: source, target: target}
    end

    test "fills a to-one relationship with the row its reference names", %{target: target} do
      assert [row] = agreed(include(Module3, :b))
      assert row.b.id == target.id
      assert row.b.c == "the to-one target"
    end

    test "fills a to-one relationship holding nothing with nothing" do
      Module3
      |> Entity.new(c_id: create(Entity.new(Module1)).id)
      |> create()

      rows = agreed(include(Module3, :b))

      assert Enum.count(rows, &is_nil(&1.b)) == 1
    end

    # What was asked for is filled and what was not keeps the sentinel naming it, which says
    # something an empty value cannot: that nobody asked.
    test "leaves the relationships the query did not ask for alone" do
      assert [row] = agreed(include(Module3, :b))
      assert row.a == %NotIncluded{relationship: :a}
      assert row.c == %NotIncluded{relationship: :c}
    end

    test "fills a to-many relationship with the rows the pairs name", %{source: source} do
      first = module_2("apple")
      second = module_2("banana")

      :ok = add_relationship(Module3, source.id, :a, first.id)
      :ok = add_relationship(Module3, source.id, :a, second.id)

      assert [row] = agreed(include(Module3, :a))
      assert matched_titles(row.a) == ["apple", "banana"]
    end

    test "fills a to-many relationship holding no pairs with an empty list" do
      assert [row] = agreed(include(Module3, :a))
      assert row.a == []
    end

    test "reads only the pairs of its own source", %{source: source} do
      other_source =
        Module3
        |> Entity.new(c_id: create(Entity.new(Module1)).id)
        |> create()

      mine = module_2("mine")
      theirs = module_2("theirs")

      :ok = add_relationship(Module3, source.id, :a, mine.id)
      :ok = add_relationship(Module3, other_source.id, :a, theirs.id)

      rows = agreed(order_by(include(Module3, :a), :id))
      row = Enum.find(rows, &(&1.id == source.id))

      assert titles(row.a) == ["mine"]
    end

    test "matches a to-many include's own filter", %{source: source} do
      kept = module_2("kept")
      dropped = module_2("dropped")

      :ok = add_relationship(Module3, source.id, :a, kept.id)
      :ok = add_relationship(Module3, source.id, :a, dropped.id)

      query = include(Module3, :a, &filter(&1, c: "kept"))

      assert [row] = agreed(query)
      assert titles(row.a) == ["kept"]
    end

    test "orders and bounds a to-many include by its own clauses", %{source: source} do
      Enum.each(["cherry", "apple", "banana"], fn title ->
        target = module_2(title)

        :ok = add_relationship(Module3, source.id, :a, target.id)
      end)

      query =
        include(Module3, :a, fn related ->
          related
          |> order_by(:c)
          |> limit(2)
        end)

      assert [row] = agreed(query)
      assert titles(row.a) == ["apple", "banana"]
    end

    test "fills what an include includes, two levels down", %{required: required, source: source} do
      Module5
      |> Entity.new(a_id: source.id)
      |> create()

      query = include(Module5, :a, &include(&1, :c))

      assert [row] = agreed(query)
      assert row.a.c.id == required.id
    end
  end

  describe "run/3 - the rows it reads" do
    test "reads the table of its own entity type and no other" do
      module_10(count: 1, username: "ada")

      Module2
      |> Entity.new(a: true, c: "not a Module10 row")
      |> create()

      assert names(agreed(Module10)) == ["ada"]
    end

    test "returns nothing for a type holding no rows" do
      assert agreed(Module10) == []
    end
  end
end
