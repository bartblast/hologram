defmodule Hologram.Query.WindowTest do
  use Hologram.Test.DatabaseCase, async: true
  use Hologram.Query

  import Hologram.Query.Window

  alias Hologram.DB
  alias Hologram.DB.QueryRunner
  alias Hologram.Query
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3

  defp term(entity_type, filter) do
    %{Query.normalize(entity_type) | filter: filter}
  end

  describe "derive/1" do
    test "downloads the type the query reads" do
      assert derive(Query.normalize(Module2)).entity == Module2
    end

    test "keeps a predicate comparing to a literal" do
      window = derive(term(Module2, [{:a, :==, true}]))

      assert window.filter == [{:a, :==, true}]
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

    test "drops a membership predicate holding a placeholder among its values" do
      window = derive(term(Module2, [{:b, :in, [1, {:placeholder, :chosen}]}]))

      assert window.filter == []
    end

    test "leaves out what a query answers rather than downloads" do
      term =
        Module2
        |> filter(a: true)
        |> order_by(:c)
        |> limit(20)
        |> offset(40)
        |> Query.normalize()

      assert derive(term) == %{
               cardinality: :set,
               entity: Module2,
               filter: [{:a, :==, true}],
               include: %{},
               limit: nil,
               offset: nil,
               order_by: []
             }
    end

    # A window is not a description of a query, it IS one, and it gets run - so it has to be a
    # term every reader of terms accepts, saying it asks for every row in no order rather than
    # leaving the question out.
    test "is a query term, runnable as one" do
      window =
        Module2
        |> filter(a: true)
        |> order_by(:c)
        |> Query.normalize()
        |> derive()

      assert is_list(QueryRunner.run(window, DB.mapping()))
    end

    test "derives the window of an included query too" do
      base_term =
        Module3
        |> include(:a)
        |> Query.normalize()

      sub_term = %{
        base_term.include.a
        | filter: [{:c, :==, {:placeholder, :search}}, {:a, :==, true}]
      }

      term = %{base_term | include: %{a: sub_term}}

      assert derive(term).include.a == %{
               cardinality: :set,
               entity: Module2,
               filter: [{:a, :==, true}],
               include: %{},
               limit: nil,
               offset: nil,
               order_by: []
             }
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
