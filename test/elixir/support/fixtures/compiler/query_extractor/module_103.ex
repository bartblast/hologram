# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module103 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Query.Stage
  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module5
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2
  alias Hologram.Test.Fixtures.Entity.Module26, as: Entity26
  alias Hologram.Test.Fixtures.Entity.Module3, as: Entity3
  alias Hologram.Test.Fixtures.Entity.Module5, as: Entity5

  prop :body, :string
  prop :min_b, :integer
  prop :n, :integer
  prop :related, Entity3
  prop :row, Entity2
  prop :search, :string
  prop :since, :datetime

  derived :bounded_by_map, [Entity2], fn min_b ->
    bounds = %{limit: 5}

    Entity2
    |> filter(b >= ^min_b)
    |> take(^bounds.limit)
  end

  derived :by_nested_field, [Entity2], fn related -> filter(Entity2, c: ^related.b.c) end

  derived :by_row_field, [Entity2], fn row -> filter(Entity2, b: ^row.b) end

  derived :by_search, [Entity2], fn search -> filter(Entity2, c: ^String.downcase(search)) end

  derived :cross_module, [Entity2], &Module5.entities_query/0

  derived :doubled, [Entity2], fn n -> filter(Entity2, b: ^(n * 2)) end

  derived :in_list, [Entity2], fn min_b -> filter(Entity2, b in [^min_b, 1]) end

  derived :included_path, [Entity5], fn since ->
    Entity5
    |> include(a.a)
    |> filter(created_at >= ^since)
  end

  derived :known_branch, [Entity2], fn ->
    floor = 100

    if Enum.member?([50, 100], floor) do
      filter(Entity2, b >= ^floor)
    else
      filter(Entity2, a: true)
    end
  end

  derived :on_stage_module, [Entity2], fn min_b -> Stage.filter(Entity2, b: {:>=, min_b}) end

  derived :quantified, [Entity26], fn body ->
    filter(Entity26, any(message <- messages, message.body == ^body))
  end

  derived :through_anonymous, [Entity3], fn since ->
    Enum.reduce([:a], Entity3, fn name, query ->
      query
      |> include(^name)
      |> filter(created_at >= ^since)
    end)
  end

  derived :through_binds, [Entity2], fn min_b ->
    base = filter(Entity2, a: true)

    filter(base, b >= ^min_b and c == ^String.upcase("abc"))
  end

  derived :through_local, [Entity2], fn min_b -> bounded_query(min_b) end

  derived :through_map, [Entity2], fn n -> filter(Entity2, b: ^Map.get(%{limit: n}, :limit)) end

  @impl Component
  def template do
    ~HOLO""
  end

  defp bounded_query(min_b) do
    filter(Entity2, b >= ^min_b)
  end
end
