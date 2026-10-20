defmodule Hologram.QueryTest do
  use Hologram.Test.BasicCase, async: true

  import Hologram.Query

  alias Hologram.Query
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module3

  describe "inspect/2" do
    test "leaves out every field at its default" do
      assert inspect(%Query{entity: Module2}) ==
               "%Hologram.Query{entity: Hologram.Test.Fixtures.Entity.Module2}"
    end

    test "prints the literal that rebuilds the term" do
      term =
        Module3
        |> filter(c_id: "x")
        |> include(:a, &filter(&1, a: true))
        |> limit(5)
        |> one()

      printed = inspect(term)

      {rebuilt, []} = Code.eval_string(printed)

      assert rebuilt == term
    end

    test "shows a counting cardinality before the entity" do
      assert inspect(count(Module2)) ==
               "%Hologram.Query{cardinality: :count, entity: Hologram.Test.Fixtures.Entity.Module2}"
    end

    test "shows an include as its nested struct" do
      term = include(Module3, :a, &filter(&1, a: true))

      assert inspect(term) ==
               "%Hologram.Query{entity: Hologram.Test.Fixtures.Entity.Module3, include: %{a: %Hologram.Query{entity: Hologram.Test.Fixtures.Entity.Module2, filter: [{:a, :==, true}]}}}"
    end

    test "shows the filter as its triples" do
      assert inspect(filter(Module2, a: true, b: {:>, 1})) ==
               "%Hologram.Query{entity: Hologram.Test.Fixtures.Entity.Module2, filter: [{:a, :==, true}, {:b, :>, 1}]}"
    end

    test "shows the ordering and the view bounds" do
      term =
        Module2
        |> order_by(:c)
        |> paginate(page: 2, size: 20)

      assert inspect(term) ==
               "%Hologram.Query{entity: Hologram.Test.Fixtures.Entity.Module2, limit: 20, offset: 20, order_by: [c: :asc]}"
    end

    test "shows the trust mark" do
      assert inspect(trust(Module2)) ==
               "%Hologram.Query{entity: Hologram.Test.Fixtures.Entity.Module2, trust: true}"
    end
  end
end
