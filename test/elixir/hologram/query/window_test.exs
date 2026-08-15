defmodule Hologram.Query.WindowTest do
  use Hologram.Test.BasicCase, async: true
  use Hologram.Query

  import Hologram.Query.Window

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

    test "drops a predicate comparing to a param" do
      window = derive(term(Module2, [{:c, :==, {:param, :search}}]))

      assert window.filter == []
    end

    test "keeps the literal predicates of a query that also has param ones" do
      window = derive(term(Module2, [{:a, :==, true}, {:c, :==, {:param, :search}}]))

      assert window.filter == [{:a, :==, true}]
    end

    test "drops a param predicate whatever the operator compares" do
      filter = [
        {:b, :!=, {:param, :excluded}},
        {:b, :<, {:param, :upper}},
        {:b, :>, {:param, :lower}},
        {:b, :in, {:param, :allowed}},
        {:b, :not_in, {:param, :denied}}
      ]

      window = derive(term(Module2, filter))

      assert window.filter == []
    end

    test "drops a membership predicate holding a param among its values" do
      window = derive(term(Module2, [{:b, :in, [1, {:param, :chosen}]}]))

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

      assert derive(term) == %{entity: Module2, filter: [{:a, :==, true}], include: %{}}
    end

    test "derives the window of an included query too" do
      base_term =
        Module3
        |> include(:a)
        |> Query.normalize()

      sub_term = %{base_term.include.a | filter: [{:c, :==, {:param, :search}}, {:a, :==, true}]}
      term = %{base_term | include: %{a: sub_term}}

      assert derive(term).include.a == %{
               entity: Module2,
               filter: [{:a, :==, true}],
               include: %{}
             }
    end

    test "gives two queries choosing different values one window" do
      searched = derive(term(Module2, [{:c, :==, {:param, :search}}]))
      chosen = derive(term(Module2, [{:a, :==, {:param, :flag}}]))

      assert searched == chosen
    end

    # Bounding it needs the thirty days written into the query, which the filter surface does not
    # offer yet - a cutoff computed per render says nothing when the window is derived.
    test "downloads a channel's whole history when its recency bound is a param" do
      filter = [{:c, :==, "channel-1"}, {:b, :>, {:param, :cutoff}}]

      window = derive(term(Module2, filter))

      assert window.filter == [{:c, :==, "channel-1"}]
    end
  end
end
