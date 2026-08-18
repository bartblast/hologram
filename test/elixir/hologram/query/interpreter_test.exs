defmodule Hologram.Query.InterpreterTest do
  use Hologram.Test.DatabaseCase, async: true
  use Hologram.Query

  import Hologram.DB.EntityOperations, only: [create: 1]
  import Hologram.Query.Interpreter

  alias Hologram.DB.Mapper
  alias Hologram.DB.QueryRunner
  alias Hologram.Entity
  alias Hologram.Query
  alias Hologram.Query.Param
  alias Hologram.Test.Fixtures.Entity.Module10
  alias Hologram.Test.Fixtures.Entity.Module2

  @mapping Mapper.derive!([Module10, Module2])

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

  # What the client holds, built from what the database holds - every row of every type, keyed
  # by id, the way the browser files them.
  defp database do
    rows =
      Map.new([Module10, Module2], fn entity_type ->
        table =
          entity_type
          |> Query.normalize()
          |> QueryRunner.run(@mapping)
          |> Map.new(&{&1.id, &1})

        {entity_type, table}
      end)

    %{facts: %{}, rows: rows}
  end

  defp module_10(attributes) do
    Module10
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

  describe "run/3 - ordering" do
    setup do
      %{
        first: module_10(count: 2, priority: 5, username: "bob"),
        second: module_10(count: 2, priority: 1, username: "ada"),
        third: module_10(count: 1, username: "cleo")
      }
    end

    test "orders by an attribute" do
      assert names(agreed(order_by(Module10, :count))) == ["cleo", "bob", "ada"]
    end

    test "orders by an attribute descending" do
      assert names(agreed(order_by(Module10, [{:count, :desc}]))) == ["bob", "ada", "cleo"]
    end

    # The rows tie on the first key, so the second decides between them - and the id appended at
    # normalization decides when every declared key has been spent.
    test "orders by each key in turn" do
      query = order_by(Module10, [:count, :priority])

      assert names(agreed(query)) == ["cleo", "ada", "bob"]
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

  describe "run/3 - params" do
    setup do
      %{
        first: module_10(count: 1, priority: 1, username: "ada"),
        second: module_10(count: 2, priority: 3, username: "bob")
      }
    end

    test "matches against the value bound to a param" do
      query = filter(Module10, priority: %Param{name: :priority})

      assert matched_names(agreed(query, bindings: %{priority: 3})) == ["bob"]
    end

    test "matches against a list bound to a param" do
      query = filter(Module10, priority: {:in, %Param{name: :priorities}})

      assert matched_names(agreed(query, bindings: %{priorities: [1, 3]})) == ["ada", "bob"]
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

    # There is nobody to compare against, so nothing answers - the same silence the database
    # gives a statement asking about an actor that is not there.
    test "matches nothing for a visitor" do
      query = filter(Module2, id: {:actor})

      assert agreed(query, actor_user_id: nil) == []
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
