# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module97 do
  use Hologram.Component
  use Hologram.DB

  alias Hologram.Test.Fixtures.Compiler.QueryExtractor.Module98
  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  prop :suffix, :string
  prop :wanted, :boolean

  derived :applied, [Entity2], fn ->
    Entity2
    |> sort(c)
    |> Module98.apply_all([true])
  end

  derived :checked, [Entity2], fn ->
    query =
      Entity2
      |> filter(a == true)
      |> Module98.keep()

    if is_nil(query), do: Entity2, else: query
  end

  derived :chosen, [Entity2], fn wanted ->
    ripe = filter(Entity2, a == true)
    sorted = sort(Entity2, c)

    if wanted, do: ripe, else: sorted
  end

  derived :from_options, [Entity2], fn ->
    Module98.from_options(base: filter(Entity2, a == true))
  end

  derived :interpolated, [Entity2], fn suffix -> filter(Entity2, c == ^"ripe #{suffix}") end

  derived :interpolated_known, [Entity2], fn -> filter(Entity2, c == ^"ripe #{:pear}") end

  derived :kept, [Entity2], fn ->
    Entity2
    |> filter(a == true)
    |> Module98.keep()
  end

  derived :kept_with_argument, [Entity2], fn wanted ->
    Entity2
    |> filter(a == ^wanted)
    |> Module98.keep()
  end

  derived :reduced, [Entity2], fn ->
    Enum.reduce([true], sort(Entity2, c), fn flag, query -> filter(query, a == ^flag) end)
  end

  @impl Component
  def template do
    ~HOLO""
  end
end
