# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryChains.Module2 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Query.Stage
  alias Hologram.Test.Fixtures.Entity.Module15, as: Entity15
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :predicates, :list

  derived :rows, [Entity2], fn -> filter(Entity2, nonexistent == true) end

  derived :secrets, [Entity15], fn -> sort(Entity15, token) end

  derived :replaced_sort, [Entity15], fn ->
    Entity15
    |> sort(token)
    |> sort(label)
  end

  derived :counted_secrets, :integer, fn ->
    Entity15
    |> sort(token)
    |> count()
  end

  derived :sorted_again_after_cut, [Entity15], fn predicates ->
    Entity15
    |> sort(token)
    |> Stage.filter(predicates)
    |> sort(label)
  end

  derived :sorted_before_cut, [Entity15], fn predicates ->
    Entity15
    |> sort(token)
    |> Stage.filter(predicates)
  end

  derived :spread_secrets, [Entity15], fn ->
    label = "x"

    Entity15
    |> filter(label == ^label)
    |> sort(token)
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
