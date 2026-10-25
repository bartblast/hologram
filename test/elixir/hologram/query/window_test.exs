defmodule Hologram.Query.WindowTest do
  use Hologram.Test.DatabaseCase, async: true
  use Hologram.DB

  import Hologram.Query.Window

  alias Hologram.DB
  alias Hologram.DB.QueryRunner
  alias Hologram.Query
  alias Hologram.Query.Stage
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3
  alias Hologram.Test.Fixtures.Entity.Module5
  alias Hologram.Test.Fixtures.Entity.Module6

  defp term(entity_type, filter) do
    %{Stage.normalize(entity_type) | filter: filter}
  end

  describe "derive/1" do
    test "downloads the type the query reads" do
      assert derive(Stage.normalize(Module2)).entity == Module2
    end

    test "keeps a predicate comparing to a literal" do
      window = derive(term(Module2, [{:a, :==, true}]))

      assert window.filter == [{:a, :==, true}]
    end

    # A comparison between two attributes says something about the row whatever value anything
    # takes, so it bounds the download the way a literal comparison does.
    test "keeps a predicate comparing two attributes" do
      window = derive(term(Module2, [{:updated_at, :>, {:attribute, :created_at}}]))

      assert window.filter == [{:updated_at, :>, {:attribute, :created_at}}]
    end

    test "keeps a path predicate comparing to a literal" do
      window = derive(term(Module3, [{[:b, :a], :==, true}]))

      assert window.filter == [{[:b, :a], :==, true}]
    end

    test "drops a predicate comparing to a placeholder" do
      window = derive(term(Module2, [{:c, :==, {:placeholder, :search}}]))

      assert window.filter == []
    end

    test "drops a predicate whose attribute is a placeholder" do
      window = derive(term(Module2, [{{:placeholder, :field}, :==, 5}]))

      assert window.filter == []
    end

    test "keeps the literal predicates of a query that also has placeholder ones" do
      filter = [
        {:a, :==, true},
        {:c, :==, {:placeholder, :search}},
        {{:placeholder, :field}, :==, 5}
      ]

      window = derive(term(Module2, filter))

      assert window.filter == [{:a, :==, true}]
    end

    test "drops a placeholder predicate whatever the operator compares" do
      filter = [
        {:b, :!=, {:placeholder, :excluded}},
        {:b, :<, {:placeholder, :upper}},
        {:b, :>, {:placeholder, :lower}},
        {:b, :in, {:placeholder, :allowed}},
        {:b, :not_in, {:placeholder, :denied}}
      ]

      window = derive(term(Module2, filter))

      assert window.filter == []
    end

    # The query answers for every value the placeholder takes, over the rows the path reads - so
    # they are downloaded even when nothing about them bounds the download.
    test "drops a path predicate comparing to a placeholder and embeds its relationships" do
      window = derive(term(Module5, [{[:a, :b, :c], :==, {:placeholder, :search}}]))

      assert window.filter == []

      assert window.include == %{
               a: %Query{entity: Module3, include: %{b: %Query{entity: Module2}}}
             }
    end

    test "drops a membership predicate holding a placeholder among its values" do
      window = derive(term(Module2, [{:b, :in, [1, {:placeholder, :chosen}]}]))

      assert window.filter == []
    end

    test "keeps a disjunction whose alternatives compare to literals" do
      filter = [{:or, [[{:a, :==, true}], [{:b, :==, 1}]]}]

      assert derive(term(Module2, filter)).filter == filter
    end

    test "narrows an alternative to its literal predicates" do
      filter = [{:or, [[{:a, :==, true}, {:c, :==, {:placeholder, :search}}], [{:b, :==, 1}]]}]

      assert derive(term(Module2, filter)).filter == [{:or, [[{:a, :==, true}], [{:b, :==, 1}]]}]
    end

    # Dropping the placeholder side alone would download only the todo rows, while the query also
    # answers for whichever rows the placeholder picks - so the alternative admits every row, and
    # the disjunction bounds nothing.
    test "drops a disjunction when an alternative loses every predicate" do
      filter = [{:or, [[{:c, :==, "todo"}], [{:b, :==, {:placeholder, :owner}}]]}]

      assert derive(term(Module2, filter)).filter == []
    end

    test "keeps the predicates beside a dropped disjunction" do
      filter = [
        {:or, [[{:c, :==, "todo"}], [{:b, :==, {:placeholder, :owner}}]]},
        {:a, :==, true}
      ]

      assert derive(term(Module2, filter)).filter == [{:a, :==, true}]
    end

    test "drops a nested disjunction the same way" do
      filter = [
        {:or,
         [
           [{:a, :==, true}, {:or, [[{:b, :==, 1}], [{:c, :==, {:placeholder, :search}}]]}],
           [{:b, :==, 2}]
         ]}
      ]

      assert derive(term(Module2, filter)).filter == [{:or, [[{:a, :==, true}], [{:b, :==, 2}]]}]
    end

    test "drops an outer disjunction when a nested one empties its alternative" do
      filter = [
        {:or,
         [[{:or, [[{:b, :==, 1}], [{:c, :==, {:placeholder, :search}}]]}], [{:a, :==, true}]]}
      ]

      assert derive(term(Module2, filter)).filter == []
    end

    # Narrowing the second alternative leaves it shorter than the first, which moves it ahead.
    test "keeps the narrowed alternatives in canonical order" do
      filter = [
        {:or,
         [
           [{:a, :==, true}, {:b, :==, 7}],
           [{:a, :==, true}, {:b, :>=, {:placeholder, :min}}]
         ]}
      ]

      assert derive(term(Module2, filter)).filter == [
               {:or, [[{:a, :==, true}], [{:a, :==, true}, {:b, :==, 7}]]}
             ]
    end

    test "gives two queries differing only in a pinned predicate of an alternative one window" do
      bounded = [{:or, [[{:c, :==, "x"}, {:b, :>=, {:placeholder, :min}}], [{:a, :==, true}]]}]
      chosen = [{:or, [[{:c, :==, "x"}, {:b, :==, {:placeholder, :one}}], [{:a, :==, true}]]}]

      assert derive(term(Module2, bounded)) == derive(term(Module2, chosen))
    end

    test "leaves out what a query answers rather than downloads" do
      term =
        Module2
        |> filter(a: true)
        |> order_by(c)
        |> limit(20)
        |> offset(40)
        |> Stage.normalize()

      assert derive(term) == %Query{entity: Module2, filter: [{:a, :==, true}]}
    end

    # A window is not a description of a query, it IS one, and it gets run - so it has to be a
    # term every reader of terms accepts, saying it asks for every row in no order rather than
    # leaving the question out.
    test "is a query term, runnable as one" do
      window =
        Module2
        |> filter(a: true)
        |> order_by(c)
        |> Stage.normalize()
        |> derive()

      assert is_list(QueryRunner.run(window, DB.mapping()))
    end

    test "embeds the relationships of a path operand" do
      window = derive(term(Module3, [{:c_id, :==, {:attribute, [:b, :id]}}]))

      assert window.include == %{b: %Query{entity: Module2}}
    end

    test "embeds the relationships of a path inside an alternative" do
      filter = [{:or, [[{[:b, :a], :==, true}], [{:c_id, :==, nil}]]}]

      assert derive(term(Module3, filter)).include == %{b: %Query{entity: Module2}}
    end

    test "embeds the relationships a path goes through inside an included query's window" do
      base_term =
        Module6
        |> include(a)
        |> Stage.normalize()

      sub_term = %{base_term.include.a | filter: [{[:b, :a], :==, true}]}
      term = %{base_term | include: %{a: sub_term}}

      assert derive(term).include.a.include == %{b: %Query{entity: Module2}}
    end

    test "merges a path's relationships into the query's own includes" do
      base_term =
        Module5
        |> include(a)
        |> Stage.normalize()

      term = %{base_term | filter: [{[:a, :b, :c], :==, "x"}]}

      assert derive(term).include == %{
               a: %Query{entity: Module3, include: %{b: %Query{entity: Module2}}}
             }
    end

    test "is a query term, runnable as one, with the relationships its paths embed" do
      window =
        Module5
        |> Stage.filter([{[:a, :b, :c], {:>=, "M"}}])
        |> Stage.normalize()
        |> derive()

      assert is_list(QueryRunner.run(window, DB.mapping()))
    end

    test "derives the window of an included query too" do
      base_term =
        Module3
        |> include(a)
        |> Stage.normalize()

      sub_term = %{
        base_term.include.a
        | filter: [{:c, :==, {:placeholder, :search}}, {:a, :==, true}]
      }

      term = %{base_term | include: %{a: sub_term}}

      assert derive(term).include.a == %Query{entity: Module2, filter: [{:a, :==, true}]}
    end

    test "gives two queries choosing different values one window" do
      searched = derive(term(Module2, [{:c, :==, {:placeholder, :search}}]))
      chosen = derive(term(Module2, [{:a, :==, {:placeholder, :flag}}]))

      assert searched == chosen
    end

    # Bounding it needs the thirty days written into the query, which the filter surface does not
    # offer yet - a cutoff computed per render says nothing when the window is derived.
    test "downloads a channel's whole history when its recency bound is a placeholder" do
      filter = [{:c, :==, "channel-1"}, {:b, :>, {:placeholder, :cutoff}}]

      window = derive(term(Module2, filter))

      assert window.filter == [{:c, :==, "channel-1"}]
    end
  end
end
