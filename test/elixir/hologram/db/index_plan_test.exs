defmodule Hologram.DB.IndexPlanTest do
  use Hologram.Test.BasicCase, async: true
  use Hologram.DB

  import Hologram.DB.IndexPlan

  alias Hologram.DB.Mapper
  alias Hologram.Query.Stage
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module10
  alias Hologram.Test.Fixtures.Entity.Module19
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module26
  alias Hologram.Test.Fixtures.Entity.Module27
  alias Hologram.Test.Fixtures.Entity.Module28
  alias Hologram.Test.Fixtures.Entity.Module29
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module32
  alias Hologram.Test.Fixtures.Entity.Module34
  alias Hologram.Test.Fixtures.Entity.Module4
  alias Hologram.Test.Fixtures.Entity.Module52
  alias Hologram.Test.Fixtures.Entity.Module54

  @mapping Mapper.derive!(
             [
               Module1,
               Module10,
               Module19,
               Module2,
               Module26,
               Module27,
               Module28,
               Module29,
               Module3,
               Module4,
               Module52,
               Module54
             ],
             []
           )

  @module10 "test_fixtures_entity_module10"
  @module19 "test_fixtures_entity_module19"
  @module2 "test_fixtures_entity_module2"
  @module26 "test_fixtures_entity_module26"
  @module3 "test_fixtures_entity_module3"
  @module4 "test_fixtures_entity_module4"
  @module54 "test_fixtures_entity_module54"

  defp need(table, eq, range \\ nil, order \\ []) do
    %{table: table, eq: MapSet.new(eq), range: range, order: order}
  end

  defp term_needs(query) do
    query
    |> Stage.normalize()
    |> needs(@mapping)
  end

  defp filter_needs(entity_type, filter) do
    entity_type
    |> Stage.normalize()
    |> Map.put(:filter, filter)
    |> needs(@mapping)
  end

  defp value(name) when name in [:count, :percent, :priority], do: 1

  defp value(:rating), do: 1.0

  defp value(:released_on), do: ~D[2026-01-01]

  defp value(_string), do: "x"

  describe "needs/2" do
    test "needs the columns equalities fix, a string by its sort key" do
      assert term_needs(filter(Module2, a == true and b == 3 and c == "x")) == [
               need(@module2, ["a", "b", "c_$sort"])
             ]
    end

    test "needs a string a unique index holds by its raw column" do
      assert term_needs(filter(Module19, slug in ["x", "y"])) == [need(@module19, ["slug"])]
    end

    test "needs a string's IS NULL only when a unique index holds its raw column" do
      assert term_needs(filter(Module19, code == nil)) == [need(@module19, ["code"])]
      assert term_needs(filter(Module19, code in [nil, "x"])) == [need(@module19, ["code"])]
    end

    test "needs the sort key of a string a unique index holds raw beside other columns" do
      membership = filter(Module19, code in ["x"] and slug in ["y"])

      taken =
        Module52
        |> filter(slug == "x")
        |> take(5)

      assert term_needs(membership) == [need(@module19, ["code_$sort", "slug_$sort"])]

      assert term_needs(taken) == [
               need("test_fixtures_entity_module52", ["slug_$sort"], nil, ["id"])
             ]
    end

    test "leaves a raw string's IS NULL out of a need a unique index serves without it" do
      assert term_needs(filter(Module19, code == nil and slug in ["x"])) == [
               need(@module19, ["slug"])
             ]
    end

    test "drops a raw string's IS NULL from a need no unique index serves" do
      assert term_needs(filter(Module54, name == nil and n2 == 1)) == [need(@module54, ["n2"])]
    end

    test "needs nothing for an IS NULL on a string a unique index holds but doesn't lead with" do
      assert term_needs(filter(Module54, s2 == nil or n4 == 1)) == []
    end

    test "keeps a raw string out of a need ordering, ranging or past a unique index's lead" do
      ordered =
        Module54
        |> filter(name == "x")
        |> sort(n1)
        |> take(5)

      assert term_needs(ordered) == [need(@module54, ["name_$sort"], nil, ["n1"])]

      assert term_needs(filter(Module19, code in ["x"] and code > "a")) == [
               need(@module19, ["code_$sort"])
             ]

      assert term_needs(filter(Module52, slug in ["x"])) == [
               need("test_fixtures_entity_module52", ["slug_$sort"])
             ]
    end

    test "keeps a raw string a unique index serves when the need orders nothing after it" do
      query =
        Module19
        |> filter(slug in ["x", "y"])
        |> take(5)

      assert term_needs(query) == [need(@module19, ["slug"])]
    end

    test "needs nothing for equalities fixing every column of a unique index" do
      id = "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f"

      assert term_needs(filter(Module19, slug == "x" and code == "y")) == []
      assert term_needs(filter(Module52, workspace_id == ^id and slug == "x")) == []
      assert term_needs(filter(Module19, slug == "x" or code == "y")) == []
    end

    test "needs a column a placeholder equality fixes" do
      assert filter_needs(Module2, [{:b, :==, {:placeholder, :count}}]) == [need(@module2, ["b"])]
    end

    test "needs a to-one's reference column and a system column" do
      id = "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f"
      created_at = ~U[2026-01-01 00:00:00Z]

      assert term_needs(filter(Module3, b_id == ^id and created_at > ^created_at)) == [
               need(@module3, ["b_id"], "created_at")
             ]
    end

    test "needs the columns memberships narrow, a placeholder list as a literal one" do
      assert term_needs(filter(Module2, b in [1, 2])) == [need(@module2, ["b"])]

      assert filter_needs(Module2, [{:c, :in, {:placeholder, :names}}]) == [
               need(@module2, ["c_$sort"])
             ]
    end

    test "needs a column an IS NULL narrows, the nil-holding membership included" do
      assert term_needs(filter(Module2, b == nil)) == [need(@module2, ["b"])]
      assert term_needs(filter(Module2, b in [nil, 1])) == [need(@module2, ["b"])]
      assert term_needs(filter(Module2, b == 1 or b == nil)) == [need(@module2, ["b"])]
    end

    test "crosses an all-nil membership, an IS NULL, with each arm of an OR beside it" do
      query = filter(Module2, b in [nil] and (a == true or c == "x"))

      assert term_needs(query) == [
               need(@module2, ["b"]),
               need(@module2, ["a", "b"]),
               need(@module2, ["b", "c_$sort"])
             ]
    end

    test "crosses a nil-holding membership, the OR it compiles to, with no OR beside it" do
      query = filter(Module2, b in [nil, 1] and (a == true or c == "x"))

      expected = [need(@module2, ["a"]), need(@module2, ["b"]), need(@module2, ["c_$sort"])]

      assert query
             |> term_needs()
             |> Enum.sort() == Enum.sort(expected)
    end

    test "needs a required string's nil-holding membership by its sort key" do
      assert term_needs(filter(Module2, c in [nil, "x"])) == [need(@module2, ["c_$sort"])]
    end

    test "needs nothing for a string's IS NULL, which reads its raw column" do
      assert filter_needs(Module2, [{:c, :==, nil}]) == []
      assert term_needs(filter(Module10, bio in [nil, "x"])) == []
    end

    test "needs a range column, a string's by its sort key" do
      assert term_needs(filter(Module2, a == true and b > 3)) == [need(@module2, ["a"], "b")]
      assert term_needs(filter(Module2, c >= "m")) == [need(@module2, [], "c_$sort")]
    end

    test "keeps the lowest range column by name when several narrow a need" do
      assert term_needs(filter(Module4, d < 1.0 and a > ^~D[2026-01-01])) == [
               need(@module4, [], "a")
             ]
    end

    test "drops a range on a column an equality fixes" do
      assert term_needs(filter(Module2, b == 3 and b > 1)) == [need(@module2, ["b"])]
    end

    test "needs nothing for conditions no index serves" do
      assert term_needs(filter(Module2, b != 3)) == []
      assert term_needs(filter(Module2, b not in [1, 2])) == []
      assert term_needs(filter(Module2, contains(c, "x"))) == []
      assert term_needs(filter(Module10, count < priority)) == []
    end

    test "needs nothing for a path, which reads the related row by its primary key" do
      assert term_needs(filter(Module3, b.c == "x")) == []
    end

    test "needs nothing for a derived value, which no column holds" do
      put_derived_definitions([Module32, Module34])
      mapping = Mapper.derive!([Module32, Module34], [])

      term =
        Module34
        |> filter(badge == "top")
        |> Stage.normalize()

      assert needs(term, mapping) == []
    end

    test "needs nothing at the row's level for a quantifier beside a condition" do
      assert term_needs(filter(Module26, name == "x" and any(m <- messages, m.body == "y"))) ==
               [need(@module26, ["name_$sort"])]
    end

    test "needs nothing for the primary key, which serves an equality on the id" do
      id = "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f"

      assert term_needs(filter(Module2, id == ^id and a == true)) == []
    end

    test "needs the conditions beside an OR and each arm with them" do
      assert term_needs(filter(Module2, a == true and (b == 1 or c == "x"))) == [
               need(@module2, ["a"]),
               need(@module2, ["a", "b"]),
               need(@module2, ["a", "c_$sort"])
             ]
    end

    test "needs an arm's own conditions with each arm of an OR nested in it" do
      date = ~D[2026-01-01]
      datetime = ~U[2026-01-01 00:00:00Z]

      query = filter(Module4, c == :x or (d == 1.0 and (a == ^date or b == ^datetime)))

      # Normalization sorts a disjunction ahead of the predicates beside it.
      assert term_needs(query) == [
               need(@module4, ["d"]),
               need(@module4, ["a", "d"]),
               need(@module4, ["b", "d"]),
               need(@module4, ["c"])
             ]
    end

    test "crosses no two ORs beside each other" do
      query = filter(Module10, (count == 1 or percent == 5) and (priority == 1 or rating == 1.0))

      assert term_needs(query) == [
               need(@module10, ["count"]),
               need(@module10, ["percent"]),
               need(@module10, ["priority"]),
               need(@module10, ["rating"])
             ]
    end

    test "needs only what's beside an OR with an arm no index serves" do
      assert term_needs(filter(Module2, a == true and (b == 1 or b != 2))) == [
               need(@module2, ["a"])
             ]

      assert term_needs(filter(Module26, name == "x" or any(m <- messages, m.body == "y"))) ==
               []
    end

    test "leaves out a repeated need" do
      assert term_needs(filter(Module2, (b == 1 and a == true) or (a == true and b == 2))) == [
               need(@module2, ["a", "b"])
             ]
    end

    test "keeps an OR adding 8 needs and drops one passing them" do
      eight = [:bio, :count, :email, :handle, :percent, :priority, :rating, :username]
      arms = Enum.map(eight, &[{&1, :==, value(&1)}])

      assert length(filter_needs(Module10, [{:or, arms}])) == 8

      ninth = [{:released_on, :==, value(:released_on)}]

      assert filter_needs(Module10, [{:country_code, :==, "pl"}, {:or, [ninth | arms]}]) == [
               need(@module10, ["country_code_$sort"])
             ]
    end

    test "counts no need toward the cap for an arm a key serves" do
      id = "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f"
      eight = [:bio, :count, :email, :handle, :percent, :priority, :rating, :username]
      arms = [[{:id, :==, id}] | Enum.map(eight, &[{&1, :==, value(&1)}])]

      assert length(filter_needs(Module10, [{:or, arms}])) == 8
    end

    test "counts an OR's repeated needs once toward the cap" do
      nine = Enum.map(1..9, &[{:b, :==, &1}])

      assert filter_needs(Module2, [{:a, :==, true}, {:or, nine}]) == [
               need(@module2, ["a"]),
               need(@module2, ["a", "b"])
             ]

      names = [:percent, :priority, :rating, :released_on]
      arms = Enum.flat_map(names, &[[{&1, :==, value(&1)}], [{&1, :==, nil}]])

      assert length(filter_needs(Module10, [{:or, [[{:count, :==, 1}] | arms]}])) == 5
    end

    test "counts the needs of ORs beside each other toward one cap" do
      pair = {:or, [[{:count, :==, 1}], [{:percent, :==, 5}]]}
      names = [:bio, :email, :handle, :priority, :rating, :released_on, :username]
      others = {:or, Enum.map(names, &[{&1, :==, value(&1)}])}

      assert filter_needs(Module10, [pair, others]) == [
               need(@module10, ["count"]),
               need(@module10, ["percent"])
             ]
    end

    test "orders a bounded statement from the index after the columns its equalities fix" do
      taken =
        Module4
        |> filter(c == :x)
        |> sort(b: :desc)
        |> take(5)

      one =
        Module4
        |> filter(c == :x)
        |> sort([a, d])
        |> one()

      assert term_needs(taken) == [need(@module4, ["c"], nil, ["b"])]
      assert term_needs(one) == [need(@module4, ["c"], nil, ["a", "d"])]
    end

    test "orders by a statement's sort columns alone when it has no filter" do
      query =
        Module4
        |> sort(b: :desc)
        |> take(5)

      assert term_needs(query) == [need(@module4, [], nil, ["b"])]
    end

    test "orders by the id when the ordering is the id alone" do
      unsorted =
        Module4
        |> filter(c == :x)
        |> take(5)

      by_id =
        Module4
        |> sort(id: :desc)
        |> one()

      assert term_needs(unsorted) == [need(@module4, ["c"], nil, ["id"])]
      assert term_needs(by_id) == [need(@module4, [], nil, ["id"])]
    end

    test "orders by a unique index's later columns after the ones its equalities fix" do
      id = "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f"

      query =
        Module52
        |> filter(workspace_id == ^id)
        |> sort(slug)
        |> take(5)

      assert term_needs(query) == [
               need("test_fixtures_entity_module52", ["workspace_id"], nil, ["slug_$sort"])
             ]
    end

    test "orders nothing from the index for a statement that bounds no rows" do
      query =
        Module4
        |> filter(c == :x)
        |> sort(b)

      skipped =
        Module4
        |> sort(b)
        |> skip(5)

      assert term_needs(query) == [need(@module4, ["c"])]
      assert term_needs(skipped) == []
    end

    test "stops the order at a change of direction and after a string's sort key" do
      mixed =
        Module4
        |> sort(a: :asc, b: :desc)
        |> take(5)

      by_string =
        Module2
        |> sort([c, b])
        |> take(5)

      assert term_needs(mixed) == [need(@module4, [], nil, ["a"])]
      assert term_needs(by_string) == [need(@module2, [], nil, ["c_$sort"])]
    end

    test "orders nothing for a placeholder ordering or a placeholder direction" do
      by_name = %{Stage.normalize(Module4) | sort: [{{:placeholder, :by}, :asc}], take: 5}
      by_direction = %{Stage.normalize(Module4) | sort: [{:b, {:placeholder, :dir}}], take: 5}

      assert needs(by_name, @mapping) == []
      assert needs(by_direction, @mapping) == []
    end

    test "skips a column an equality fixes, wherever the ordering names it" do
      fixed_first =
        Module4
        |> filter(c == :x)
        |> sort(c: :asc, b: :desc, d: :desc)
        |> take(5)

      fixed_string =
        Module2
        |> filter(c == "x")
        |> sort([c, b])
        |> take(5)

      assert term_needs(fixed_first) == [need(@module4, ["c"], nil, ["b", "d"])]
      assert term_needs(fixed_string) == [need(@module2, ["c_$sort"], nil, ["b"])]
    end

    test "orders nothing after a membership or an IS NULL" do
      membership =
        Module4
        |> filter(c in [:x, :y])
        |> sort(b)
        |> take(5)

      missing =
        Module2
        |> filter(b == nil)
        |> sort(a)
        |> take(5)

      assert term_needs(membership) == [need(@module4, ["c"])]
      assert term_needs(missing) == [need(@module2, ["b"])]
    end

    test "orders after a range when the ordering leads with the range's column" do
      query =
        Module4
        |> filter(c == :x and b > ^~U[2026-01-01 00:00:00Z])
        |> sort([b, d])
        |> take(5)

      assert term_needs(query) == [need(@module4, ["c"], "b", ["d"])]
    end

    test "keeps the range the ordering leads with over a lower one by name" do
      query =
        Module4
        |> filter(a > ^~D[2026-01-01] and d < 1.0)
        |> sort(d)
        |> take(5)

      assert term_needs(query) == [need(@module4, [], "d")]
    end

    test "orders nothing after a range on another column" do
      query =
        Module4
        |> filter(a > ^~D[2026-01-01])
        |> sort(d)
        |> take(5)

      assert term_needs(query) == [need(@module4, [], "a")]
    end

    test "orders nothing for a statement with an OR an index serves" do
      query =
        Module4
        |> filter(c == :x or d == 1.0)
        |> sort(b)
        |> take(5)

      assert term_needs(query) == [need(@module4, ["c"]), need(@module4, ["d"])]
    end

    test "orders after the conditions beside an OR no index serves" do
      query =
        Module4
        |> filter(c == :x and (d == 1.0 or d != 2.0))
        |> sort(b)
        |> take(5)

      assert term_needs(query) == [need(@module4, ["c"], nil, ["b"])]
    end
  end
end
