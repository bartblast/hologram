defmodule Hologram.DB.IndexPlanTest do
  use Hologram.Test.BasicCase, async: true
  use Hologram.DB

  import Hologram.DB.IndexPlan

  alias Hologram.Commons.CryptographicUtils
  alias Hologram.Commons.PLT
  alias Hologram.Compiler
  alias Hologram.DB.Mapper
  alias Hologram.Policy
  alias Hologram.Query.Stage
  alias Hologram.Test.Fixtures.Entity.Module1
  alias Hologram.Test.Fixtures.Entity.Module10
  alias Hologram.Test.Fixtures.Entity.Module14
  alias Hologram.Test.Fixtures.Entity.Module19
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module26
  alias Hologram.Test.Fixtures.Entity.Module27
  alias Hologram.Test.Fixtures.Entity.Module28
  alias Hologram.Test.Fixtures.Entity.Module29
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module32
  alias Hologram.Test.Fixtures.Entity.Module33
  alias Hologram.Test.Fixtures.Entity.Module34
  alias Hologram.Test.Fixtures.Entity.Module37
  alias Hologram.Test.Fixtures.Entity.Module38
  alias Hologram.Test.Fixtures.Entity.Module39
  alias Hologram.Test.Fixtures.Entity.Module4
  alias Hologram.Test.Fixtures.Entity.Module40
  alias Hologram.Test.Fixtures.Entity.Module41
  alias Hologram.Test.Fixtures.Entity.Module50
  alias Hologram.Test.Fixtures.Entity.Module51
  alias Hologram.Test.Fixtures.Entity.Module52
  alias Hologram.Test.Fixtures.Entity.Module54
  alias Hologram.Test.Fixtures.Entity.Module55
  alias Hologram.Test.Fixtures.Entity.Module56
  alias Hologram.Test.Fixtures.Entity.Module57

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
  @module28 "test_fixtures_entity_module28"
  @module3 "test_fixtures_entity_module3"
  @module33 "test_fixtures_entity_module33"
  @module38 "test_fixtures_entity_module38"
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

  # A path of the test's own in the temp dir. The OS process goes before the counter, which is unique
  # within one VM only, so two test runs on one machine never share a path (see
  # Hologram.Test.ScratchDatabaseCase).
  defp own_tmp_path(name) do
    Path.join(
      System.tmp_dir!(),
      "#{name}_#{System.pid()}_#{System.unique_integer([:positive])}.plt"
    )
  end

  # Dumps the given needs the way the build does, at a path of the test's own.
  defp write_dump(needs) do
    path = own_tmp_path("index_needs")
    on_exit(fn -> File.rm(path) end)

    {plt, _dump_path} = Compiler.build_index_needs_plt(needs, build_dir: System.tmp_dir!())
    PLT.dump(plt, path)

    path
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
      query = filter(Module26, name == "x" and any(m <- messages, m.body == "y"))

      assert term_needs(query) == [
               need(@module26, ["name_$sort"]),
               need(@module28, ["body_$sort", "channel_id"]),
               need(@module28, ["body_$sort"])
             ]
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

      query = filter(Module26, name == "x" or any(m <- messages, m.body == "y"))

      assert term_needs(query) == [need(@module28, ["body_$sort", "channel_id"])]
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

    test "orders nothing for a placeholder ordering" do
      by_name = %{Stage.normalize(Module4) | sort: [{{:placeholder, :by}, :asc}], take: 5}

      assert needs(by_name, @mapping) == []
    end

    test "orders by the leading column of a placeholder direction, and by nothing after it" do
      dir = {:placeholder, :dir}
      leading = %{Stage.normalize(Module4) | sort: [{:b, dir}, {:d, :asc}], take: 5}
      following = %{Stage.normalize(Module4) | sort: [{:b, :asc}, {:d, dir}], take: 5}

      assert needs(leading, @mapping) == [need(@module4, [], nil, ["b"])]
      assert needs(following, @mapping) == [need(@module4, [], nil, ["b"])]
    end

    test "orders by the leading column of a placeholder direction after a column an equality fixes" do
      filtered =
        Module4
        |> filter(c == :x)
        |> Stage.normalize()

      query = %{
        filtered
        | sort: [{:c, :asc}, {:b, {:placeholder, :dir}}, {:d, :asc}],
          take: 5
      }

      assert needs(query, @mapping) == [need(@module4, ["c"], nil, ["b"])]
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

  describe "needs/2 for the levels below the queried row" do
    setup do
      put_derived_definitions([Module32, Module33, Module37, Module38, Module55])

      %{
        derived_mapping:
          Mapper.derive!([Module1, Module2, Module32, Module33, Module37, Module38, Module55], [])
      }
    end

    test "needs an inverse of a to-one's reference column with the quantifier's conditions" do
      query = filter(Module26, none(m <- messages, m.body == "y" and m.position > 1))

      assert term_needs(query) == [need(@module28, ["body_$sort", "channel_id"], "position")]
    end

    test "needs the conditions of a top-level any over an inverse of a to-one alone as well" do
      query = filter(Module26, any(m <- messages, m.body == "y"))

      assert term_needs(query) == [
               need(@module28, ["body_$sort", "channel_id"]),
               need(@module28, ["body_$sort"])
             ]
    end

    test "needs only the reference column for an all, whose conditions no index serves" do
      query = filter(Module26, all(m <- messages, m.position == 1 or m.body == "y"))

      assert term_needs(query) == [need(@module28, ["channel_id"])]
    end

    test "needs each arm of an OR in a quantifier's condition with the reference column" do
      query = filter(Module26, none(m <- messages, m.body == "y" or m.position == 1))

      assert term_needs(query) == [
               need(@module28, ["channel_id"]),
               need(@module28, ["body_$sort", "channel_id"]),
               need(@module28, ["channel_id", "position"])
             ]
    end

    test "needs the reference column of the last link of a source" do
      through_to_one = filter(Module28, none(m <- channel.messages, m.position == 1))
      flattened = filter(Module29, none(m <- messages.channel.messages, m.position == 1))

      assert term_needs(through_to_one) == [need(@module28, ["channel_id", "position"])]
      assert term_needs(flattened) == [need(@module28, ["channel_id", "position"])]
    end

    test "needs the reference column of a set before the last link of a source" do
      assert term_needs(filter(Module26, none(l <- messages.labels, l.name == "x"))) == [
               need(@module28, ["channel_id"])
             ]
    end

    test "needs no range against the row above for a level read before that row", %{
      derived_mapping: mapping
    } do
      term =
        Module37
        |> filter(any(m <- messages, m.created_at > last_read_at))
        |> Stage.normalize()

      assert needs(term, mapping) == [need(@module38, ["channel_id"], "created_at")]
    end

    test "needs the reference column of a set before a derived count's last link" do
      put_derived_definitions([Module34, Module39, Module40])

      mapping =
        Mapper.derive!(
          [Module1, Module2, Module32, Module33, Module34, Module39, Module40, Module41],
          []
        )

      term =
        Module40
        |> filter(note_tag_count > 0)
        |> Stage.normalize()

      assert needs(term, mapping) == [need("test_fixtures_entity_module41", ["team_id"])]
    end

    test "needs what the sort of a derived set bounded by a skip reads" do
      put_derived_definitions([Module56, Module57])
      mapping = Mapper.derive!([Module56, Module57], [])

      term =
        Module56
        |> filter(any(i <- rest, i.position == 1))
        |> Stage.normalize()

      assert needs(term, mapping) == [
               need("test_fixtures_entity_module57", ["owner_id"]),
               need("test_fixtures_entity_module57", ["owner_id"], "position")
             ]
    end

    test "needs nothing for a set read through a join table" do
      assert term_needs(filter(Module28, any(l <- labels, l.name == "x"))) == []
      assert term_needs(filter(Module28, none(l <- labels, l.name == "x"))) == []
    end

    test "needs the levels of a quantifier nested in a quantifier's condition" do
      query = filter(Module29, any(m <- messages, any(n <- m.channel.messages, n.position == 1)))

      assert term_needs(query) == [need(@module28, ["channel_id", "position"])]
    end

    test "needs the set of a quantifier whose source starts at the row above" do
      term =
        Module26
        |> Stage.filter(any: {[:messages], [any: {{:outer, 1, [:messages]}, [position: 1]}]})
        |> Stage.normalize()

      assert needs(term, @mapping) == [
               need(@module28, ["channel_id"]),
               need(@module28, ["channel_id", "position"])
             ]
    end

    test "needs a counted set's reference column with its conditions", %{derived_mapping: mapping} do
      term =
        Module37
        |> filter(pinned_count > 3)
        |> Stage.normalize()

      assert needs(term, mapping) == [need(@module38, ["channel_id", "pinned"])]
    end

    test "needs a range a counted set compares with the row it is counted for", %{
      derived_mapping: mapping
    } do
      term =
        Module37
        |> filter(unread_count > 0)
        |> Stage.normalize()

      assert needs(term, mapping) == [need(@module38, ["channel_id"], "created_at")]
    end

    test "needs the count an attribute operand or a path reads", %{derived_mapping: mapping} do
      operand =
        Module33
        |> filter(position < later_count)
        |> Stage.normalize()

      path =
        Module38
        |> filter(channel.pinned_count > 3)
        |> Stage.normalize()

      assert needs(operand, mapping) == [need(@module33, ["channel_id"], "position")]
      assert needs(path, mapping) == [need(@module38, ["channel_id", "pinned"])]
    end

    test "needs the count the last link of a longer source reads", %{derived_mapping: mapping} do
      term =
        Module38
        |> filter(sibling_count > 1)
        |> Stage.normalize()

      assert needs(term, mapping) == [need(@module38, ["channel_id"])]
    end

    test "needs the count a derived condition reads", %{derived_mapping: mapping} do
      term =
        Module37
        |> filter(busy == true)
        |> Stage.normalize()

      assert needs(term, mapping) == [need(@module38, ["channel_id", "pinned"])]
    end

    test "needs the count a field reads through a related row, a condition or a join", %{
      derived_mapping: mapping
    } do
      pinned = need(@module38, ["channel_id", "pinned"])

      for query <- [
            filter(Module55, channel_pinned > 1),
            filter(Module55, status == "busy"),
            filter(Module55, tag == "busy!")
          ] do
        assert query
               |> Stage.normalize()
               |> needs(mapping) == [pinned]
      end
    end

    test "needs the count a sort reads", %{derived_mapping: mapping} do
      term =
        Module37
        |> sort(pinned_count)
        |> Stage.normalize()

      assert needs(term, mapping) == [need(@module38, ["channel_id", "pinned"])]
    end

    test "needs the count an include of a derived value reads", %{derived_mapping: mapping} do
      term =
        Module37
        |> include(pinned_count)
        |> Stage.normalize()

      assert needs(term, mapping) == [need(@module38, ["channel_id", "pinned"])]
    end

    test "orders a bounded derived set from the index after its reference column", %{
      derived_mapping: mapping
    } do
      channel_term =
        Module37
        |> include(recent_messages)
        |> Stage.normalize()

      board_term =
        Module32
        |> filter(any(m <- recent_messages, m.body == "x"))
        |> Stage.normalize()

      assert needs(channel_term, mapping) == [
               need(@module38, ["channel_id"], nil, ["created_at"])
             ]

      assert needs(board_term, mapping) == [need(@module33, ["channel_id"], nil, ["position"])]
    end

    test "needs every set a derived field may choose, and those of a set it reads", %{
      derived_mapping: mapping
    } do
      included =
        Module37
        |> include(picked)
        |> Stage.normalize()

      counted =
        Module37
        |> filter(picked_count > 0)
        |> Stage.normalize()

      expected = [need(@module38, ["channel_id"], nil, ["id"]), need(@module38, ["channel_id"])]

      assert included
             |> needs(mapping)
             |> Enum.sort() == Enum.sort(expected)

      assert counted
             |> needs(mapping)
             |> Enum.sort() == Enum.sort(expected)
    end

    test "needs an included inverse of a to-one's reference column, at every depth" do
      term =
        Module29
        |> include(messages.channel.messages)
        |> Stage.normalize()

      assert term_needs(term) == [need(@module28, ["channel_id"])]
    end

    test "needs nothing for an include through a join table or a to-one" do
      assert term_needs(include(Module28, [channel, labels])) == []
    end

    test "needs nothing for a reference column a unique index serves" do
      assert term_needs(include(Module26, topic)) == []
    end

    test "needs nothing for the includes of a count, which reads none" do
      term =
        Module26
        |> include(messages)
        |> count()

      assert term_needs(term) == []
    end
  end

  describe "needs/3 with read rules" do
    defp rule(entity_type, predicates, to \\ nil) do
      %{predicates: Stage.predicate_triples!(entity_type, predicates), to: to, via: nil}
    end

    defp rule_needs(term, rules, anonymous? \\ false) do
      term
      |> Stage.normalize()
      |> needs(@mapping, %{anonymous?: anonymous?, rules: rules})
    end

    @owner "018f4571-a1b2-7c3d-8e4f-5a6b7c8d9e0f"

    test "needs what a rule's predicates fix" do
      rules = [rule(Module2, a: true)]

      assert rule_needs(Module2, rules) == [need(@module2, ["a"])]
    end

    test "needs each rule of the group beside the filter's need, crossing none" do
      rules = [rule(Module2, a: true), rule(Module2, c: "x")]

      assert rule_needs(filter(Module2, b == 1), rules) == [
               need(@module2, ["b"]),
               need(@module2, ["a"]),
               need(@module2, ["c_$sort"])
             ]
    end

    test "needs a column the acting user fixes" do
      rules = [rule(Module3, c_id: {:actor})]

      assert rule_needs(Module3, rules) == [need(@module3, ["c_id"])]
    end

    test "needs nothing of the rules when one asks only for a role" do
      rules = [rule(Module2, a: true), rule(Module2, [], [{:own, [:member]}])]

      assert rule_needs(filter(Module2, b == 1), rules) == [need(@module2, ["b"])]
    end

    test "needs the predicates of a rule asking for a role beside them" do
      rules = [rule(Module2, [a: true], [{:own, [:member]}]), rule(Module2, c: "x")]

      assert rule_needs(Module2, rules) == [need(@module2, ["a"]), need(@module2, ["c_$sort"])]
    end

    test "needs what's left of the rules for an anonymous session" do
      rules = [
        rule(Module3, c_id: {:actor}),
        rule(Module3, [], [{:own, [:member]}]),
        rule(Module3, b_id: @owner)
      ]

      assert rule_needs(Module3, rules) == []
      assert rule_needs(Module3, rules, true) == [need(@module3, ["b_id"])]
    end

    test "needs nothing of rules a rule asking nothing drops, or rules nobody satisfies" do
      assert rule_needs(Module2, [rule(Module2, a: true), rule(Module2, [])]) == []
      assert rule_needs(Module3, [rule(Module3, c_id: {:actor})], true) == []
    end

    test "needs each arm of an OR in a rule" do
      rules = [rule(Module2, or: [[a: true], [b: 1]])]

      assert rule_needs(Module2, rules) == [need(@module2, ["a"]), need(@module2, ["b"])]
    end

    test "needs the related rows a rule's quantifier reads, a lone rule's at the top" do
      quantifier = Stage.predicate_triples!(Module26, any: {[:messages], [position: 1]})
      quantified = %{predicates: quantifier, to: nil, via: nil}

      assert rule_needs(Module26, [quantified]) == [
               need(@module28, ["channel_id", "position"]),
               need(@module28, ["position"])
             ]

      assert rule_needs(Module26, [quantified, rule(Module26, name: "x")]) == [
               need(@module28, ["channel_id", "position"])
             ]
    end

    test "leaves out a rule delegating to a type that grants nothing" do
      never = %{predicates: [], to: nil, via: {:read, [:b], []}}

      assert rule_needs(Module3, [never, rule(Module3, b_id: @owner)]) == [
               need(@module3, ["b_id"])
             ]
    end

    test "leaves out a declared delegation to a type declaring no rule" do
      mapping = Mapper.derive!([Module50, Module51], [])
      [delegation] = Policy.build(Module51).read
      rules = [delegation, rule(Module51, parent_id: @owner)]

      term = Stage.normalize(Module51)

      assert needs(term, mapping, %{rules: rules}) == [
               need("test_fixtures_entity_module51", ["parent_id"])
             ]
    end

    test "leaves out a delegation an anonymous session folds every target rule of away" do
      target_rules = [rule(Module2, [], [{:own, [:member]}]), rule(Module2, id: {:actor})]
      delegation = %{predicates: [], to: nil, via: {:read, [:b], target_rules}}
      rules = [delegation, rule(Module3, b_id: @owner)]

      assert rule_needs(Module3, rules) == []
      assert rule_needs(Module3, rules, true) == [need(@module3, ["b_id"])]
    end

    test "leaves out a delegation whose target's only rule never holds" do
      nested = %{predicates: [], to: nil, via: {:read, [:topic], []}}
      delegation = %{predicates: [], to: nil, via: {:read, [:channel], [nested]}}

      assert rule_needs(Module28, [delegation, rule(Module28, position: 1)]) == [
               need(@module28, ["position"])
             ]
    end

    test "needs nothing of the rules when one asks only for a delegation that holds" do
      holding = %{predicates: [], to: nil, via: {:read, [:b], [rule(Module2, [])]}}

      assert rule_needs(Module3, [holding, rule(Module3, b_id: @owner)]) == []
    end

    test "needs nothing of the rules' quantifiers when a rule asking nothing drops the group" do
      quantifier = Stage.predicate_triples!(Module26, any: {[:messages], [position: 1]})
      rules = [%{predicates: quantifier, to: nil, via: nil}, rule(Module26, [])]

      assert rule_needs(Module26, rules) == []
    end

    test "needs nothing of an empty rule list, which reads no rows" do
      assert rule_needs(Module2, []) == []
    end

    test "needs no rule for a key that serves it, and the other rules of the group" do
      rules = [rule(Module2, id: @owner), rule(Module2, a: true)]

      assert rule_needs(Module2, rules) == [need(@module2, ["a"])]
    end

    test "orders nothing after a rule's conditions, though the filter's need does" do
      query =
        Module4
        |> filter(c == :x)
        |> sort(b)
        |> take(5)

      assert rule_needs(query, [rule(Module4, d: 1.0)]) == [
               need(@module4, ["c"], nil, ["b"]),
               need(@module4, ["d"])
             ]
    end

    test "needs what a derived field a rule reads reads" do
      put_derived_definitions([Module37, Module38])
      mapping = Mapper.derive!([Module1, Module2, Module37, Module38], [])

      term = Stage.normalize(Module37)
      rules = [rule(Module37, pinned_count: {:>, 3})]

      assert needs(term, mapping, %{rules: rules}) == [need(@module38, ["channel_id", "pinned"])]
    end

    test "needs none of the read rules of an included type" do
      put_derived_definitions([Module34, Module39, Module40])

      mapping =
        Mapper.derive!(
          [Module1, Module2, Module32, Module33, Module34, Module39, Module40, Module41],
          []
        )

      term =
        Module40
        |> include(notes)
        |> Stage.normalize()

      assert needs(term, mapping, %{rules: [rule(Module40, name: "x")]}) == [
               need("test_fixtures_entity_module41", ["team_id"]),
               need("test_fixtures_entity_module40", ["name_$sort"])
             ]
    end
  end

  describe "dumped_needs/1" do
    test "reads the needs the build dumped" do
      needs = [need(@module2, ["b"])]

      dump_path = write_dump(needs)

      assert dumped_needs(dump_path) == needs
    end

    test "needs nothing when there is no dump" do
      assert dumped_needs(own_tmp_path("no_index_needs")) == []
    end
  end

  describe "owned_index_names/1" do
    test "names the plain btree indexes named ...$idx that aren't unique" do
      plain = %{columns: ["a"], nulls_distinct: true, unique: false}

      schema = %{
        tables: %{
          "task" => %{
            indexes: %{
              "task_a_$idx" => plain,
              "task_a_$uidx" => %{plain | unique: true},
              "task_b_$idx" => Map.put(plain, :non_plain, [:predicate]),
              "task_c_$idx" => %{plain | unique: true},
              "hand_made" => plain
            }
          },
          "project" => %{indexes: %{"project_a_$idx" => plain}}
        }
      }

      assert owned_index_names(schema) == MapSet.new(["project_a_$idx", "task_a_$idx"])
    end
  end

  describe "plan/2" do
    test "plans the framework's needs and the dumped ones" do
      mapping = Mapper.derive!([Module1, Module2, Module3], [])
      needs = [need(@module2, ["b"])]

      dump_path = write_dump(needs)

      expected_plan =
        mapping
        |> framework_needs()
        |> Enum.concat(needs)
        |> select(mapping)

      assert plan(mapping, dump_path) == expected_plan
      assert Map.has_key?(expected_plan, @module2)
    end

    test "leaves out a dumped need naming a table the mapping no longer holds" do
      mapping = Mapper.derive!([Module1, Module3], [])
      dump_path = write_dump([need(@module2, ["b"])])

      assert plan(mapping, dump_path) == select(framework_needs(mapping), mapping)
    end
  end

  describe "framework_needs/1" do
    test "needs each reference column and each join table's reverse direction" do
      mapping = Mapper.derive!([Module1, Module2, Module3], [])

      assert framework_needs(mapping) == [
               need(@module3, ["b_id"]),
               need(@module3, ["c_id"]),
               need("test_fixtures_entity_module3_a_$join", ["target_id"], nil, ["source_id"])
             ]
    end

    test "needs the grant store's lookup of the grants on an entity" do
      mapping = Mapper.derive!([Module14], [])

      grant_need = need("hologram_role_grant", ["entity_type"], nil, ["entity_id", "role"])

      assert grant_need in framework_needs(mapping)
    end
  end

  describe "select/2" do
    defp index(columns), do: %{columns: columns, nulls_distinct: true, unique: false}

    defp index_name(table_segments, columns),
      do: Mapper.fit_identifier(table_segments, columns, "$idx")

    @module4_segments ["test", "fixtures", "entity", "module4"]

    test "merges needs whose equality columns nest into one index" do
      needs = [need(@module4, ["c"]), need(@module4, ["a", "c"]), need(@module4, ["a", "c", "d"])]

      assert select(needs, @mapping) == %{
               @module4 => %{
                 index_name(@module4_segments, ["c", "a", "d"]) => index(["c", "a", "d"])
               }
             }
    end

    test "gives the same plan whatever order the needs come in" do
      needs = [
        need(@module4, ["c"]),
        need(@module4, ["a", "c"]),
        need(@module4, ["d"], "b"),
        need(@module4, ["a"], nil, ["b"]),
        need(@module4, ["d"])
      ]

      expected = %{
        @module4 => %{
          index_name(@module4_segments, ["c", "a"]) => index(["c", "a"]),
          index_name(@module4_segments, ["d", "b"]) => index(["d", "b"]),
          index_name(@module4_segments, ["a", "b"]) => index(["a", "b"])
        }
      }

      assert select(needs, @mapping) == expected
      assert select(Enum.reverse(needs), @mapping) == expected
    end

    test "starts an index of its own for a need fixing a column an index ranges or orders by" do
      ranged = [need(@module4, ["c"], "b"), need(@module4, ["c", "d"])]
      ordered = [need(@module4, ["a", "c"]), need(@module4, ["a"], nil, ["d"])]

      assert select(ranged, @mapping) == %{
               @module4 => %{
                 index_name(@module4_segments, ["c", "b"]) => index(["c", "b"]),
                 index_name(@module4_segments, ["c", "d"]) => index(["c", "d"])
               }
             }

      assert select(ordered, @mapping) == %{
               @module4 => %{
                 index_name(@module4_segments, ["a", "c"]) => index(["a", "c"]),
                 index_name(@module4_segments, ["a", "d"]) => index(["a", "d"])
               }
             }
    end

    test "extends an index ending in a range with a need fixing every column it holds" do
      needs = [need(@module4, ["c"], "b"), need(@module4, ["b", "c"], nil, ["d"])]

      assert select(needs, @mapping) == %{
               @module4 => %{
                 index_name(@module4_segments, ["c", "b", "d"]) => index(["c", "b", "d"])
               }
             }
    end

    test "drops an index whose columns lead another's" do
      ranged = [need(@module4, ["a"], "b"), need(@module4, ["a"], "b", ["d"])]
      ordered = [need(@module4, ["a"], nil, ["b"]), need(@module4, ["a", "b"], nil, ["d"])]

      for needs <- [ranged, ordered] do
        assert select(needs, @mapping) == %{
                 @module4 => %{
                   index_name(@module4_segments, ["a", "b", "d"]) => index(["a", "b", "d"])
                 }
               }
      end
    end

    test "serves a need from an index the plan chose for another" do
      needs = [need(@module4, ["a", "c"]), need(@module4, ["a"], nil, ["c"])]

      assert select(needs, @mapping) == %{
               @module4 => %{index_name(@module4_segments, ["a", "c"]) => index(["a", "c"])}
             }
    end

    test "serves a need from an index leading with its equality columns in another order" do
      needs = [
        need(@module4, ["c"]),
        need(@module4, ["a", "c"], nil, ["b"]),
        need(@module4, ["a", "c"], "b")
      ]

      assert select(needs, @mapping) == %{
               @module4 => %{
                 index_name(@module4_segments, ["c", "a", "b"]) => index(["c", "a", "b"])
               }
             }
    end

    test "extends the largest index it can, the first chosen among equals" do
      first = [need(@module4, ["a"]), need(@module4, ["c"]), need(@module4, ["a", "c"])]

      largest = [
        need(@module4, ["a"]),
        need(@module4, ["a", "c"]),
        need(@module4, ["d"]),
        need(@module4, ["a", "c", "d"])
      ]

      assert select(first, @mapping) == %{
               @module4 => %{
                 index_name(@module4_segments, ["a", "c"]) => index(["a", "c"]),
                 index_name(@module4_segments, ["c"]) => index(["c"])
               }
             }

      assert select(largest, @mapping) == %{
               @module4 => %{
                 index_name(@module4_segments, ["a", "c", "d"]) => index(["a", "c", "d"]),
                 index_name(@module4_segments, ["d"]) => index(["d"])
               }
             }
    end

    test "places the needs by their equality columns, ranging and ordering ones among them" do
      needs = [
        need(@module4, ["a", "c", "d"], nil, ["b"]),
        need(@module4, ["d"]),
        need(@module4, ["a", "d"], "b", ["c"]),
        need(@module4, [], "a", ["d", "c", "b"]),
        need(@module4, ["a"])
      ]

      columns =
        select(needs, @mapping)[@module4]
        |> Map.values()
        |> Enum.map(& &1.columns)
        |> Enum.sort()

      assert columns == [["a", "d", "c", "b"], ["d", "a", "b", "c"]]
    end

    test "serves a need from an index whose leading columns it fixes" do
      needs = [need(@module4, ["a", "c"]), need(@module4, ["c", "a"], "b"), need(@module4, ["a"])]

      assert select(needs, @mapping) == %{
               @module4 => %{
                 index_name(@module4_segments, ["a", "c", "b"]) => index(["a", "c", "b"])
               }
             }
    end

    test "gives two needs no columns lead together indexes of their own" do
      needs = [need(@module4, ["a"]), need(@module4, ["c"])]

      assert select(needs, @mapping) == %{
               @module4 => %{
                 index_name(@module4_segments, ["a"]) => index(["a"]),
                 index_name(@module4_segments, ["c"]) => index(["c"])
               }
             }
    end

    test "adds nothing for a need the primary key or a unique index serves" do
      assert select([need(@module19, ["slug"]), need(@module19, ["id"])], @mapping) == %{}

      key_lead = need("test_fixtures_entity_module52", ["workspace_id"])
      join_source = need("test_fixtures_entity_module3_a_$join", ["source_id"])
      unique_to_one = need("test_fixtures_entity_module27", ["channel_id"])

      assert select([key_lead, join_source, unique_to_one], @mapping) == %{}
    end

    test "leaves out a need naming a raw string no unique index serves" do
      mapping = Mapper.derive!([Module14], [])

      assert select([need("test_fixtures_entity_module14", ["email"])], mapping) == %{}
    end

    test "gives a join table's reverse direction an index its primary key can't serve" do
      mapping = Mapper.derive!([Module1, Module2, Module3], [])
      [join_table] = mapping[Module3].join_tables

      plan =
        mapping
        |> framework_needs()
        |> select(mapping)

      assert plan[join_table.name] == %{
               "test_fixtures_entity_module3_a_$join_target_id_source_id_$idx" =>
                 index(["target_id", "source_id"])
             }
    end

    test "keeps the grant store's index in the order the recheck reads it" do
      mapping = Mapper.derive!([Module14], [])

      plan =
        mapping
        |> framework_needs()
        |> select(mapping)

      # Its identity index leads with the user, so the user's reference needs no index of its own.
      assert plan["hologram_role_grant"] == %{
               "hologram_role_grant_entity_type_entity_id_role_$idx" =>
                 index(["entity_type", "entity_id", "role"]),
               "hologram_role_grant_granted_by_id_$idx" => index(["granted_by_id"])
             }
    end

    test "keeps the grant store's index beside an app's reads of the store" do
      mapping = Mapper.derive!([Module14], [])

      app_needs = [
        need("hologram_role_grant", ["entity_id", "entity_type"]),
        need("hologram_role_grant", ["entity_id", "entity_type"], nil, ["created_at"]),
        need("hologram_role_grant", ["entity_type"], nil, ["created_at"])
      ]

      plan =
        mapping
        |> framework_needs()
        |> Enum.concat(app_needs)
        |> select(mapping)

      assert plan["hologram_role_grant"]["hologram_role_grant_entity_type_entity_id_role_$idx"] ==
               index(["entity_type", "entity_id", "role"])
    end

    test "leaves out a need naming a table or a column the mapping doesn't hold" do
      needs = [need(@module4, ["gone"]), need("gone_table", ["a"])]

      assert select(needs, @mapping) == %{}
    end

    test "fits a name over the identifier limit" do
      columns = ["count", "n1", "n2", "n3", "n4", "name_$sort", "s1_$sort"]
      segments = ["test", "fixtures", "entity", "module54"]
      expected_columns = Enum.sort(columns)

      plan = select([need(@module54, columns)], @mapping)
      [{name, definition}] = Map.to_list(plan[@module54])

      assert name == index_name(segments, expected_columns)
      assert name != Enum.join(segments ++ expected_columns, "_") <> "_$idx"
      assert byte_size(name) <= 63
      assert definition == index(expected_columns)
    end

    test "raises on two reference columns deriving the same index name" do
      defmodule Ref do
        use Hologram.Entity

        relationship :b_c, Module1
      end

      defmodule RefB do
        use Hologram.Entity

        relationship :c, Module1
      end

      mapping = Mapper.derive!([Module1, Ref, RefB], [])

      message =
        normalize_newlines("""
        colliding derived names - rename the declarations so that every derived name is unique:
          * index "db_index_plan_test_ref_b_c_id_$idx" is derived from an index on Hologram.DB.IndexPlanTest.Ref by b_c_id, an index on Hologram.DB.IndexPlanTest.RefB by c_id\
        """)

      assert_raise Hologram.CompileError, message, fn -> framework_plan(mapping) end
    end

    test "keeps an index to the first 32 columns, PostgreSQL's limit" do
      defmodule Wide do
        use Hologram.Entity

        for name <- [
              :a01,
              :a02,
              :a03,
              :a04,
              :a05,
              :a06,
              :a07,
              :a08,
              :a09,
              :a10,
              :a11,
              :a12,
              :a13,
              :a14,
              :a15,
              :a16,
              :a17,
              :a18,
              :a19,
              :a20,
              :a21,
              :a22,
              :a23,
              :a24,
              :a25,
              :a26,
              :a27,
              :a28,
              :a29,
              :a30,
              :a31,
              :a32,
              :a33
            ] do
          attribute name, :integer
        end
      end

      mapping = Mapper.derive!([Wide], [])
      table = mapping[Wide].table
      columns = for n <- 1..33, do: "a#{String.pad_leading(Integer.to_string(n), 2, "0")}"

      assert %{^table => indexes} = select([need(table, columns)], mapping)
      assert [%{columns: index_columns}] = Map.values(indexes)
      assert index_columns == Enum.take(columns, 32)
    end

    test "gives the later of two indexes of one table deriving one name a digest of its columns" do
      defmodule Pub do
        use Hologram.Entity

        attribute :public, :boolean
        attribute :public_id, :integer
      end

      mapping = Mapper.derive!([Pub], [])
      table = mapping[Pub].table
      segments = Mapper.table_segments(Pub)
      digest = CryptographicUtils.short_digest("public_id", 4)

      assert select([need(table, ["public"], nil, ["id"]), need(table, ["public_id"])], mapping) ==
               %{
                 table => %{
                   index_name(segments, ["public", "id"]) => index(["public", "id"]),
                   index_name(segments, ["public_id", digest]) => index(["public_id"])
                 }
               }
    end

    test "raises on two tables deriving the same index name" do
      defmodule Foo do
        use Hologram.Entity

        attribute :bar_baz, :integer
      end

      defmodule FooBar do
        use Hologram.Entity

        attribute :baz, :integer
      end

      mapping = Mapper.derive!([Foo, FooBar], [])
      foo = mapping[Foo].table
      foo_bar = mapping[FooBar].table

      message =
        normalize_newlines("""
        colliding derived names - rename the declarations so that every derived name is unique:
          * index "db_index_plan_test_foo_bar_baz_$idx" is derived from an index on Hologram.DB.IndexPlanTest.Foo by bar_baz, an index on Hologram.DB.IndexPlanTest.FooBar by baz\
        """)

      assert_raise Hologram.CompileError, message, fn ->
        select([need(foo, ["bar_baz"]), need(foo_bar, ["baz"])], mapping)
      end
    end
  end
end
