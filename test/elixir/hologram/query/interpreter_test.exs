defmodule Hologram.Query.InterpreterTest do
  use Hologram.Test.DatabaseCase, async: true
  use Hologram.DB

  import Hologram.DB.EntityOperations, only: [add_relationship: 4, create: 1]
  import Hologram.Query.Interpreter

  alias Hologram.DB.Codec
  alias Hologram.DB.Connection
  alias Hologram.DB.Mapper
  alias Hologram.DB.QueryRunner
  alias Hologram.Entity.NotIncluded
  alias Hologram.Query.Placeholder
  alias Hologram.Query.Stage
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module10
  alias Hologram.Test.Fixtures.Entity.Module13
  alias Hologram.Test.Fixtures.Entity.Module15
  alias Hologram.Test.Fixtures.Entity.Module17
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module24
  alias Hologram.Test.Fixtures.Entity.Module25
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module4
  alias Hologram.Test.Fixtures.Entity.Module5

  @entity_types [
    Module1,
    Module10,
    Module13,
    Module15,
    Module17,
    Module2,
    Module24,
    Module25,
    Module3,
    Module4,
    Module5
  ]

  @mapping Mapper.derive!(@entity_types, [])

  # The whole point of this module: the same term over the same rows, run by the database and by
  # the interpreter, agreeing. Every test goes through here and then asserts what came back, so
  # that two empty results never pass for agreement.
  defp agreed(query, opts \\ []) do
    term = Stage.normalize(query)
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

  defp created(entity_type, attributes) do
    {:ok, entity} =
      attributes
      |> entity_type.new()
      |> create()

    entity
  end

  # What the client holds, built from what the database holds - every row of every type keyed by
  # id, and every to-many pair, the way the browser files them.
  defp database do
    rows =
      Map.new(@entity_types, fn entity_type ->
        table =
          entity_type
          |> Stage.normalize()
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
    {:ok, entity} =
      attributes
      |> Module10.new()
      |> create()

    entity
  end

  defp module_17(attributes) do
    {:ok, entity} =
      attributes
      |> Module17.new()
      |> create()

    entity
  end

  # Ids are time-ordered but not strictly so within a millisecond, and a query with no order of
  # its own falls back to them - so what a MATCHING test asserts is which rows came back, not
  # the order the tiebreaker happened to put them in.
  defp matched_names(rows) do
    rows
    |> names()
    |> Enum.sort()
  end

  defp module_24(attributes) do
    {:ok, entity} =
      attributes
      |> Module24.new()
      |> create()

    entity
  end

  defp module_2(title) do
    {:ok, entity} =
      %{a: true, c: title}
      |> Module2.new()
      |> create()

    entity
  end

  defp matched_ids(rows) do
    rows
    |> Enum.map(& &1.id)
    |> Enum.sort()
  end

  defp matched_titles(rows) do
    rows
    |> titles()
    |> Enum.sort()
  end

  defp matched_module_17_labels(rows) do
    rows
    |> module_17_labels()
    |> Enum.sort()
  end

  defp module_17_labels(rows), do: Enum.map(rows, & &1.label)

  defp names(rows), do: Enum.map(rows, & &1.username)

  # What a client holds for the given actor: the rows each type's read policy admits, which is what
  # a policied statement reads a path's hops through.
  defp readable_database(actor_user_id) do
    rows =
      Map.new(@entity_types, fn entity_type ->
        table =
          entity_type
          |> Stage.normalize()
          |> QueryRunner.run_policied(@mapping, actor_user_id)
          |> Map.new(&{&1.id, &1})

        {entity_type, table}
      end)

    %{facts: %{}, rows: rows}
  end

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
      assert matched_names(agreed(filter(Module10, priority != 3))) == ["ada", "cleo"]
    end

    test "matches an unset attribute" do
      assert matched_names(agreed(filter(Module10, priority: nil))) == ["cleo"]
    end

    test "matches what is set" do
      assert matched_names(agreed(filter(Module10, priority != nil))) == ["ada", "bob"]
    end

    test "matches membership in a list" do
      assert matched_names(agreed(filter(Module10, priority in [1, 3]))) == ["ada", "bob"]
    end

    test "matches membership in a list naming an unset value" do
      assert matched_names(agreed(filter(Module10, priority in [nil, 3]))) == ["bob", "cleo"]
    end

    # A list without nil leaves the rows that have no value at all outside it, so excluding the
    # list keeps them.
    test "matches exclusion from a list, missing values included" do
      assert matched_names(agreed(filter(Module10, priority not in [1]))) == ["bob", "cleo"]
    end

    test "matches exclusion from a list naming an unset value" do
      assert matched_names(agreed(filter(Module10, priority not in [nil, 1]))) == ["bob"]
    end

    test "matches every predicate of a filter and no fewer" do
      query = filter(Module10, count >= 2 and priority != nil)

      assert names(agreed(query)) == ["bob"]
    end
  end

  describe "run/3 - disjunctions" do
    setup do
      %{
        first: module_10(count: 1, priority: 1, username: "ada"),
        second: module_10(count: 2, priority: 3, username: "bob"),
        third: module_10(count: 3, username: "cleo")
      }
    end

    test "matches either alternative" do
      assert matched_names(agreed(filter(Module10, priority == 1 or count == 2))) == [
               "ada",
               "bob"
             ]
    end

    test "matches a conjunction inside an alternative" do
      query = filter(Module10, (count >= 2 and priority == 3) or username == "ada")

      assert matched_names(agreed(query)) == ["ada", "bob"]
    end

    test "matches a grouped disjunction inside a conjunction" do
      query = filter(Module10, count >= 2 and (priority == 1 or username == "cleo"))

      assert matched_names(agreed(query)) == ["cleo"]
    end

    test "matches a nested disjunction" do
      query =
        filter(Module10, count == 1 or (count >= 2 and (priority == 3 or username == "cleo")))

      assert matched_names(agreed(query)) == ["ada", "bob", "cleo"]
    end

    # An ordering comparison passes over a missing value, and the other alternative still holds -
    # nil means inside a disjunction what it means outside one.
    test "passes an unset value to the other alternative" do
      assert matched_names(agreed(filter(Module10, priority > 1 or count == 3))) == [
               "bob",
               "cleo"
             ]
    end

    test "matches an unset value through equality in an alternative" do
      query = filter(Module10, priority == nil or count == 1)

      assert matched_names(agreed(query)) == ["ada", "cleo"]
    end

    test "matches a disjunction beside the conjuncts around it" do
      query =
        Module10
        |> filter(count >= 2)
        |> filter(priority == 3 or username == "cleo")

      assert matched_names(agreed(query)) == ["bob", "cleo"]
    end

    test "matches nothing when no alternative holds" do
      assert agreed(filter(Module10, priority == 5 or count == 9)) == []
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
      assert matched_names(agreed(filter(Module10, count > 1))) == ["bob", "cleo"]
    end

    test "matches values at or above a bound" do
      assert matched_names(agreed(filter(Module10, count >= 5))) == ["bob", "cleo"]
    end

    test "matches values below a bound" do
      assert matched_names(agreed(filter(Module10, count < 5))) == ["ada"]
    end

    test "matches values at or below a bound" do
      assert matched_names(agreed(filter(Module10, count <= 5))) == ["ada", "bob"]
    end

    test "compares floats" do
      assert matched_names(agreed(filter(Module10, rating > 2.0))) == ["bob"]
    end

    test "compares dates" do
      assert matched_names(agreed(filter(Module10, released_on >= ^~D[2027-01-01]))) == [
               "bob"
             ]
    end

    test "compares datetimes" do
      query = filter(Module10, held_at < ^~U[2027-01-01 00:00:00Z])

      assert names(agreed(query)) == ["ada"]
    end

    test "matches a range as its two bounds" do
      assert matched_names(agreed(filter(Module10, count in 1..5))) == ["ada", "bob"]
    end

    # An ordering line has no place to put a value that is not there, so a comparison passes
    # over the rows that have none - unlike the equality family, which counts them.
    test "passes over an unset attribute, whichever way the comparison points" do
      assert matched_names(agreed(filter(Module10, rating > 0.0))) == ["ada", "bob"]
      assert matched_names(agreed(filter(Module10, rating < 100.0))) == ["ada", "bob"]
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
      assert names(agreed(sort(Module10, count))) == ["cleo", "ada", "bob"]
    end

    test "orders by an attribute descending" do
      assert names(agreed(sort(Module10, count: :desc))) == ["bob", "ada", "cleo"]
    end

    # The rows tie on the first key, so the second decides between them.
    test "orders by each key in turn" do
      module_10(count: 7, priority: 5, username: "eve")
      module_10(count: 7, priority: 1, username: "dana")

      query =
        Module10
        |> filter(count: 7)
        |> sort([count, priority])

      assert names(agreed(query)) == ["dana", "eve"]
    end

    # Ascending puts them last and descending puts them first, which is where the database puts
    # them - a page reading its own rows shows them where the server would have.
    test "places missing values last when ascending" do
      assert names(agreed(sort(Module10, priority))) == ["ada", "bob", "cleo"]
    end

    test "places missing values first when descending" do
      assert names(agreed(sort(Module10, priority: :desc))) == ["cleo", "bob", "ada"]
    end

    test "orders strings" do
      assert names(agreed(sort(Module10, username))) == ["ada", "bob", "cleo"]
    end
  end

  describe "run/3 - ordering strings by their sort keys" do
    test "orders by the derived key rather than by the bytes" do
      module_10(count: 1, username: "Zoe")
      module_10(count: 2, username: "ada")
      module_10(count: 3, username: "Ödön")
      module_10(count: 4, username: "bob")

      assert names(agreed(sort(Module10, username))) == ["ada", "bob", "Ödön", "Zoe"]
    end
  end

  describe "run/3 - ordering enums" do
    setup do
      %{
        first: module_17(priority: :medium, label: "a"),
        second: module_17(priority: :high, label: "b"),
        third: module_17(priority: :low, label: "c"),
        fourth: module_17(label: "d")
      }
    end

    # Declared, alphabetical and reverse-alphabetical are three different sequences for these
    # values, so an order that matches the declared one matches it on purpose.
    test "orders by the declared position, not the label" do
      assert module_17_labels(agreed(sort(Module17, priority))) == ["c", "a", "b", "d"]
    end

    test "orders by the declared position descending" do
      query = sort(Module17, priority: :desc)

      assert module_17_labels(agreed(query)) == ["d", "b", "a", "c"]
    end

    test "settles a tie on an enum by the next key" do
      module_17(priority: :medium, label: "e")
      module_17(priority: :medium, label: "f")

      query = sort(Module17, [priority, label])

      assert module_17_labels(agreed(query)) == ["c", "a", "e", "f", "b", "d"]
    end
  end

  describe "run/3 - comparing attributes" do
    setup do
      %{
        first: module_10(count: 1, priority: 3, rating: 1.5, username: "ada"),
        second: module_10(count: 5, priority: 5, rating: 4.5, username: "bob"),
        third: module_10(count: 9, username: "cleo"),
        fourth: module_10(count: 2, priority: 1, rating: 2.0, username: "dan")
      }
    end

    test "matches rows whose attribute is below another" do
      assert matched_names(agreed(filter(Module10, count < priority))) == ["ada"]
    end

    test "matches rows whose attribute is at or above another" do
      assert matched_names(agreed(filter(Module10, count >= priority))) == ["bob", "dan"]
    end

    test "matches rows whose attributes are equal" do
      assert matched_names(agreed(filter(Module10, count == priority))) == ["bob"]
    end

    test "matches rows whose attributes differ, a missing one included" do
      assert matched_names(agreed(filter(Module10, count != priority))) == ["ada", "cleo", "dan"]
    end

    # An ordering line has no place for a value that is not there, on either side - cleo has no
    # priority, so no spelling of the comparison reaches her. A number sorts before nil as a term,
    # and the browser reads a missing value as 0, so each tier would let one pair of spellings
    # through if it compared the missing value at all - the four keep the two suites alike.
    test "passes over a row missing either side of an ordering comparison" do
      assert matched_names(agreed(filter(Module10, count <= priority))) == ["ada", "bob"]
      assert matched_names(agreed(filter(Module10, priority >= count))) == ["ada", "bob"]
      assert matched_names(agreed(filter(Module10, count >= priority))) == ["bob", "dan"]
      assert matched_names(agreed(filter(Module10, priority <= count))) == ["bob", "dan"]
    end

    test "matches two missing attributes as equal" do
      unset = module_24(%{})
      half_set = module_24(starts_on: ~D[2026-03-01])
      both_set = module_24(ends_on: ~D[2026-03-01], starts_on: ~D[2026-03-01])

      assert matched_ids(agreed(filter(Module24, starts_on == ends_on))) ==
               Enum.sort([both_set.id, unset.id])

      assert matched_ids(agreed(filter(Module24, starts_on != ends_on))) == [half_set.id]
    end

    test "compares two dates" do
      reversed = module_24(ends_on: ~D[2026-03-01], starts_on: ~D[2026-03-05])
      module_24(ends_on: ~D[2026-03-05], starts_on: ~D[2026-03-01])

      assert matched_ids(agreed(filter(Module24, ends_on < starts_on))) == [reversed.id]
    end

    # Dan's 2 equals 2.0, so the two types compare as numbers on both tiers.
    test "compares an integer with a float" do
      assert matched_names(agreed(filter(Module10, count < rating))) == ["ada"]
      assert matched_names(agreed(filter(Module10, count == rating))) == ["dan"]
    end

    # Declared order, not label order: :high is after :medium in the declared list and before it as
    # an atom, so a label comparison would match nothing here.
    test "compares two enums by their declared position" do
      above = module_24(level: :high, priority: :medium)
      below = module_24(level: :low, priority: :medium)
      level = module_24(level: :medium, priority: :medium)

      assert matched_ids(agreed(filter(Module24, level > priority))) == [above.id]

      assert matched_ids(agreed(filter(Module24, level <= priority))) ==
               Enum.sort([below.id, level.id])
    end

    # Mango and mango share a key, so the values settle it - and Łódź folds to lodz, before m.
    test "compares two strings by their keys, then by their values" do
      module_10(bio: "mango", count: 1, username: "Mango")
      module_10(bio: "apple", count: 1, username: "Zebra")
      module_10(bio: "m", count: 1, username: "Łódź")

      assert matched_names(agreed(filter(Module10, username < bio))) == ["Mango", "Łódź"]
      assert matched_names(agreed(filter(Module10, username > bio))) == ["Zebra"]
    end

    test "matches an attribute comparison inside an alternative" do
      query = filter(Module10, count < priority or username == "cleo")

      assert matched_names(agreed(query)) == ["ada", "cleo"]
    end

    test "binds a placeholder beside an attribute comparison" do
      query = filter(Module10, count >= priority and username == ^%Placeholder{name: :name})

      assert matched_names(agreed(query, bindings: %{name: "dan"})) == ["dan"]
    end
  end

  describe "run/3 - comparing enums" do
    setup do
      %{
        first: module_17(priority: :medium, label: "a"),
        second: module_17(priority: :high, label: "b"),
        third: module_17(priority: :low, label: "c"),
        fourth: module_17(label: "d")
      }
    end

    # Declared order, not label order: :high is the LAST declared value, so a label comparison
    # would drop it here and keep :low, which is what makes this discriminate.
    test "matches values at or after a declared value" do
      query = filter(Module17, priority >= :medium)

      assert matched_module_17_labels(agreed(query)) == ["a", "b"]
    end

    test "matches values before a declared value" do
      query = filter(Module17, priority < :medium)

      assert matched_module_17_labels(agreed(query)) == ["c"]
    end

    # Compared as atoms, :high sorts before :medium and would drop out - so only the ranks the
    # alternative's predicate is collected for keep it.
    test "compares an enum inside an alternative by its declared position" do
      query = filter(Module17, priority >= :medium or label == "d")

      assert matched_module_17_labels(agreed(query)) == ["a", "b", "d"]
    end

    test "passes over an unset enum" do
      query = filter(Module17, priority >= :low)

      assert matched_module_17_labels(agreed(query)) == ["a", "b", "c"]
    end

    test "compares a declared value bound to a placeholder" do
      query = filter(Module17, priority >= ^%Placeholder{name: :min})

      assert matched_module_17_labels(agreed(query, bindings: %{min: :medium})) == ["a", "b"]
    end

    # The database executor refuses the binding before it builds a statement, so an undeclared
    # label never reaches Postgres there - and the interpreter refuses it in the same words.
    test "refuses a placeholder bound to a value the enum does not declare, as the database does" do
      term =
        Module17
        |> filter(priority >= ^%Placeholder{name: :min})
        |> Stage.normalize()

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

  # A bound is a position in the list `sort` renders, so what sorts at or after it is what the
  # comparison matches - the key carries the order and the value settles the ties.
  describe "run/3 - comparing strings" do
    setup do
      Enum.each(["Zürich", "Łódź", "apple", "Mango", "Zebra", "zebra"], &module_2/1)

      :ok
    end

    test "matches values at or after a bound by their key" do
      assert matched_titles(agreed(filter(Module2, c >= "m"))) == [
               "Mango",
               "Zebra",
               "Zürich",
               "zebra"
             ]
    end

    test "matches values before a bound by their key" do
      assert matched_titles(agreed(filter(Module2, c < "m"))) == ["apple", "Łódź"]
    end

    test "settles a bound that shares a key by the value itself" do
      assert matched_titles(agreed(filter(Module2, c > "Zebra"))) == ["Zürich", "zebra"]
    end

    test "passes over an unset string" do
      module_10(count: 1)

      assert names(agreed(filter(Module10, username >= "a"))) == []
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
        |> sort(count)
        |> limit(2)

      assert names(agreed(query)) == ["ada", "bob"]
    end

    test "skips the offset" do
      query =
        Module10
        |> sort(count)
        |> offset(1)

      assert names(agreed(query)) == ["bob", "cleo"]
    end

    test "skips before it takes" do
      query =
        Module10
        |> sort(count)
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
        |> sort(count)
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
        |> filter(priority != nil)
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

  describe "run/3 - paths" do
    setup do
      early =
        created(Module4, a: ~D[2026-01-01], b: ~U[2099-01-01 00:00:00.000000Z], c: :x, d: 1.5)

      late =
        created(Module4, a: ~D[2026-06-01], b: ~U[2001-01-01 00:00:00.000000Z], c: :y, d: 3.0)

      high =
        created(Module24,
          ends_on: ~D[2026-02-01],
          level: :low,
          priority: :high,
          starts_on: ~D[2026-01-01]
        )

      low = created(Module24, level: :low, priority: :low)

      %{
        first: created(Module25, e_id: high.id, f_id: early.id),
        second: created(Module25, e_id: low.id, f_id: late.id),
        third: created(Module25, f_id: early.id)
      }
    end

    test "matches a value one hop away", %{second: second} do
      assert matched_ids(agreed(filter(Module25, f.c == :y))) == [second.id]
    end

    test "matches a value two hops away" do
      required = DB.create!(Module1.new())
      target = module_2("the target")

      {:ok, middle} =
        %{b_id: target.id, c_id: required.id}
        |> Module3.new()
        |> create()

      {:ok, source} =
        %{a_id: middle.id}
        |> Module5.new()
        |> create()

      assert matched_ids(agreed(filter(Module5, a.b.c == "the target"))) == [source.id]
    end

    test "compares a path's enum by its declared position", %{first: first} do
      assert matched_ids(agreed(filter(Module25, e.priority >= :medium))) == [first.id]
    end

    test "compares a path's date", %{first: first, third: third} do
      assert matched_ids(agreed(filter(Module25, f.a < ^~D[2026-03-01]))) ==
               Enum.sort([first.id, third.id])
    end

    # The sort key folds case, so a bound reaches "Mango" the way the list sorts it - a path reads
    # the key of the row it leads to.
    test "compares a path's string by its sort key" do
      early =
        created(Module4, a: ~D[2026-01-01], b: ~U[2026-01-01 00:00:00.000000Z], c: :x, d: 1.5)

      ids =
        Map.new(["apple", "Mango", "zebra"], fn label ->
          target = created(Module15, label: label, token: "tok")

          {label, created(Module25, f_id: early.id, g_id: target.id).id}
        end)

      assert matched_ids(agreed(filter(Module25, g.label >= "M"))) ==
               Enum.sort([ids["Mango"], ids["zebra"]])
    end

    test "compares a path with an attribute of the row", %{first: first, third: third} do
      assert matched_ids(agreed(filter(Module25, created_at < f.b))) ==
               Enum.sort([first.id, third.id])
    end

    # The third row has no e, so both sides read as missing there - equal, the way two missing
    # attributes of a row are, and never ordered.
    test "compares two paths", %{first: first, second: second, third: third} do
      assert matched_ids(agreed(filter(Module25, e.priority == e.level))) ==
               Enum.sort([second.id, third.id])

      assert matched_ids(agreed(filter(Module25, e.starts_on < e.ends_on))) == [first.id]
    end

    test "binds a placeholder on a path", %{first: first} do
      base_term = Stage.normalize(Module25)
      term = %{base_term | filter: [{[:e, :priority], :==, {:placeholder, :priority}}]}

      assert matched_ids(agreed(term, bindings: %{priority: :high})) == [first.id]
    end

    test "matches a path inside an alternative", %{first: first, second: second} do
      assert matched_ids(agreed(filter(Module25, f.c == :y or e.priority == :high))) ==
               Enum.sort([first.id, second.id])
    end

    # A path through an empty relationship reads as missing, so each operator answers for the third
    # row what it answers for an attribute that holds nothing.
    test "passes a path through an empty relationship to the nil rules", %{
      first: first,
      second: second,
      third: third
    } do
      assert matched_ids(agreed(filter(Module25, e.priority == :low))) == [second.id]

      assert matched_ids(agreed(filter(Module25, e.priority != :low))) ==
               Enum.sort([first.id, third.id])

      assert matched_ids(agreed(filter(Module25, e.priority == nil))) == [third.id]

      assert matched_ids(agreed(filter(Module25, e.priority not in [:low]))) ==
               Enum.sort([first.id, third.id])

      assert matched_ids(agreed(filter(Module25, e.priority > :low))) == [first.id]
    end

    # The database never holds a reference to a row that is not there, but a client can - a fill
    # arrives in pieces - so this one is the interpreter's alone.
    test "reads a reference to a row the database does not hold as missing", %{
      first: first,
      second: second,
      third: third
    } do
      database = put_in(database().rows[Module24], %{})

      term =
        Module25
        |> filter(e.priority == nil)
        |> Stage.normalize()

      assert matched_ids(run(term, database)) == Enum.sort([first.id, second.id, third.id])
    end
  end

  describe "run/3 - paths under a read policy" do
    setup do
      early =
        created(Module4, a: ~D[2026-01-01], b: ~U[2026-01-01 00:00:00.000000Z], c: :x, d: 1.5)

      shown = created(Module13, public: true, title: "shown")
      hidden = created(Module13, public: false, title: "hidden")

      %{
        hidden_one: created(Module25, f_id: early.id, h_id: hidden.id),
        no_one: created(Module25, f_id: early.id),
        shown_one: created(Module25, f_id: early.id, h_id: shown.id)
      }
    end

    # A row the session may not read is not in what it holds, so the path through it reads as
    # missing on both tiers - the answer an include of it gives.
    test "reads a row the read policy hides as missing", %{
      hidden_one: hidden_one,
      no_one: no_one,
      shown_one: shown_one
    } do
      hidden_title =
        Module25
        |> filter(h.title == "hidden")
        |> Stage.normalize()

      missing_title =
        Module25
        |> filter(h.title == nil)
        |> Stage.normalize()

      shown_title =
        Module25
        |> filter(h.title == "shown")
        |> Stage.normalize()

      for term <- [hidden_title, missing_title, shown_title] do
        assert run(term, readable_database(nil)) == QueryRunner.run_policied(term, @mapping, nil)
      end

      assert matched_ids(QueryRunner.run_policied(hidden_title, @mapping, nil)) == []

      assert matched_ids(QueryRunner.run_policied(missing_title, @mapping, nil)) ==
               Enum.sort([hidden_one.id, no_one.id])

      assert matched_ids(QueryRunner.run_policied(shown_title, @mapping, nil)) == [shown_one.id]
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
      query = filter(Module10, priority: ^%Placeholder{name: :priority})

      assert matched_names(agreed(query, bindings: %{priority: 3})) == ["bob"]
    end

    test "matches against a placeholder inside an alternative" do
      query = filter(Module10, priority == ^%Placeholder{name: :priority} or count == 2)

      assert matched_names(agreed(query, bindings: %{priority: 1})) == ["ada", "bob"]
    end

    test "matches against a list bound to a placeholder" do
      query = filter(Module10, priority in ^%Placeholder{name: :priorities})

      assert matched_names(agreed(query, bindings: %{priorities: [1, 3]})) == ["ada", "bob"]
    end

    # Identity with the database covers what each REFUSES, not only what each answers - so a
    # binding the caller did not give is a caller error here too, rather than a filter nothing
    # passes. Each refusal is asserted of BOTH, which is the only way the messages are held
    # together.
    test "refuses a placeholder the bindings do not name, as the database does" do
      term =
        Module10
        |> filter(priority: ^%Placeholder{name: :priority})
        |> Stage.normalize()

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
        |> filter(priority: ^%Placeholder{name: :priority})
        |> Stage.normalize()

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
        |> filter(priority in ^%Placeholder{name: :priorities})
        |> Stage.normalize()

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
      query = filter(Module2, id == ^{:actor})

      assert titles(agreed(query, actor_user_id: second.id)) == ["second"]
    end

    test "matches everything but who is asking", %{first: first} do
      query = filter(Module2, id != ^{:actor})

      assert titles(agreed(query, actor_user_id: first.id)) == ["second"]
    end

    test "matches an alternative naming who is asking", %{first: first} do
      query = filter(Module2, id == ^{:actor} or c == "second")

      assert matched_titles(agreed(query, actor_user_id: first.id)) == ["first", "second"]
    end

    # The alternative asking about the visitor answers nothing, and the other one still answers.
    test "passes a visitor to the alternative that names nobody" do
      query = filter(Module2, id == ^{:actor} or c == "second")

      assert titles(agreed(query, actor_user_id: nil)) == ["second"]
    end

    test "matches nothing for a visitor when every alternative names them" do
      query = filter(Module2, id == ^{:actor} or id != ^{:actor})

      assert agreed(query, actor_user_id: nil) == []
    end

    # There is nobody to compare against, so nothing answers - the same silence the database
    # gives a statement asking about an actor that is not there.
    test "matches nothing for a visitor" do
      query = filter(Module2, id == ^{:actor})

      assert agreed(query, actor_user_id: nil) == []
    end

    # The negated form is where that silence has to be deliberate: nobody is UNEQUAL to every
    # row, so a predicate left to compare against nothing would answer with everything.
    test "matches nothing for a visitor, whichever way the predicate points" do
      query = filter(Module2, id != ^{:actor})

      assert agreed(query, actor_user_id: nil) == []
    end
  end

  describe "run/3 - includes" do
    setup do
      {:ok, required} = create(Module1.new())

      target = module_2("the to-one target")

      {:ok, source} =
        %{b_id: target.id, c_id: required.id}
        |> Module3.new()
        |> create()

      %{required: required, source: source, target: target}
    end

    test "fills a to-one relationship with the row its reference names", %{target: target} do
      assert [row] = agreed(include(Module3, b))
      assert row.b.id == target.id
      assert row.b.c == "the to-one target"
    end

    test "fills a to-one relationship holding nothing with nothing" do
      {:ok, required} = create(Module1.new())

      {:ok, _entity} =
        %{c_id: required.id}
        |> Module3.new()
        |> create()

      rows = agreed(include(Module3, b))

      assert Enum.count(rows, &is_nil(&1.b)) == 1
    end

    # What was asked for is filled and what was not keeps the sentinel naming it, which says
    # something an empty value cannot: that nobody asked.
    test "leaves the relationships the query did not ask for alone" do
      assert [row] = agreed(include(Module3, b))
      assert row.a == %NotIncluded{relationship: :a}
      assert row.c == %NotIncluded{relationship: :c}
    end

    test "fills a to-many relationship with the rows the pairs name", %{source: source} do
      first = module_2("apple")
      second = module_2("banana")

      :ok = add_relationship(Module3, source.id, :a, first.id)
      :ok = add_relationship(Module3, source.id, :a, second.id)

      assert [row] = agreed(include(Module3, a))
      assert matched_titles(row.a) == ["apple", "banana"]
    end

    test "fills a to-many relationship holding no pairs with an empty list" do
      assert [row] = agreed(include(Module3, a))
      assert row.a == []
    end

    test "reads only the pairs of its own source", %{source: source} do
      {:ok, required} = create(Module1.new())

      {:ok, other_source} =
        %{c_id: required.id}
        |> Module3.new()
        |> create()

      mine = module_2("mine")
      theirs = module_2("theirs")

      :ok = add_relationship(Module3, source.id, :a, mine.id)
      :ok = add_relationship(Module3, other_source.id, :a, theirs.id)

      rows = agreed(sort(include(Module3, a), id))
      row = Enum.find(rows, &(&1.id == source.id))

      assert titles(row.a) == ["mine"]
    end

    test "matches a to-many include's own filter", %{source: source} do
      kept = module_2("kept")
      dropped = module_2("dropped")

      :ok = add_relationship(Module3, source.id, :a, kept.id)
      :ok = add_relationship(Module3, source.id, :a, dropped.id)

      query = include(Module3, a, &filter(&1, c: "kept"))

      assert [row] = agreed(query)
      assert titles(row.a) == ["kept"]
    end

    test "matches a disjunction in a to-many include's own filter", %{source: source} do
      apple = module_2("apple")
      banana = module_2("banana")
      cherry = module_2("cherry")

      :ok = add_relationship(Module3, source.id, :a, apple.id)
      :ok = add_relationship(Module3, source.id, :a, banana.id)
      :ok = add_relationship(Module3, source.id, :a, cherry.id)

      query = include(Module3, a, &filter(&1, c == "apple" or c == "cherry"))

      assert [row] = agreed(query)
      assert matched_titles(row.a) == ["apple", "cherry"]
    end

    test "orders and bounds a to-many include by its own clauses", %{source: source} do
      Enum.each(["cherry", "apple", "banana"], fn title ->
        target = module_2(title)

        :ok = add_relationship(Module3, source.id, :a, target.id)
      end)

      query =
        include(Module3, a, fn related ->
          related
          |> sort(c)
          |> limit(2)
        end)

      assert [row] = agreed(query)
      assert titles(row.a) == ["apple", "banana"]
    end

    test "fills what an include includes, two levels down", %{required: required, source: source} do
      {:ok, _entity} =
        %{a_id: source.id}
        |> Module5.new()
        |> create()

      query = include(Module5, a, &include(&1, c))

      assert [row] = agreed(query)
      assert row.a.c.id == required.id
    end

    test "fills what an include includes, three levels down", %{source: source} do
      rows =
        Enum.reduce(1..4, [], fn _level, created ->
          parent_id =
            case created do
              [] -> nil
              [parent | _earlier] -> parent.id
            end

          {:ok, entity} =
            %{a_id: source.id, b_id: parent_id}
            |> Module5.new()
            |> create()

          [entity | created]
        end)

      [deepest | _rest] = rows
      root = List.last(rows)

      matched = agreed(include(Module5, b.b.b))
      row = Enum.find(matched, &(&1.id == deepest.id))

      assert row.b.b.b.id == root.id
    end
  end

  describe "run/3 - the rows it reads" do
    test "reads the table of its own entity type and no other" do
      module_10(count: 1, username: "ada")

      {:ok, _entity} =
        %{a: true, c: "not a Module10 row"}
        |> Module2.new()
        |> create()

      assert names(agreed(Module10)) == ["ada"]
    end

    test "returns nothing for a type holding no rows" do
      assert agreed(Module10) == []
    end
  end
end
