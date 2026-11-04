# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module56 do
  # Query helpers whose clause a known argument decides.

  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  def bounded(min_b, limit) when limit > 10 do
    Entity2
    |> filter(b >= ^min_b)
    |> take(10)
  end

  def bounded(min_b, limit) do
    Entity2
    |> filter(b >= ^min_b)
    |> take(^limit)
  end

  def by_kind(:open, min_b), do: filter(Entity2, b >= ^min_b)

  def by_kind(:all, _min_b), do: Entity2

  def case_kind(min_b, kind) do
    case kind do
      :open -> filter(Entity2, b >= ^min_b)
      :all -> Entity2
    end
  end

  def listed(min_b, ids) when length(ids) > 2 do
    Entity2
    |> filter(b >= ^min_b)
    |> take(2)
  end

  def listed(min_b, _ids), do: filter(Entity2, b >= ^min_b)

  def mixed(nil, _mode), do: filter(Entity2, a: true)

  def mixed(_min_b, :never), do: filter(Entity2, c: "never")

  def mixed(min_b, _mode), do: filter(Entity2, b >= ^min_b)

  def paired(min_b, kind) do
    size = if kind == :few, do: :small, else: :large
    limit = if kind == :few, do: 1, else: 10

    pick(min_b, size, limit)
  end

  def pick(min_b, :small, 1) do
    Entity2
    |> filter(b >= ^min_b)
    |> take(1)
  end

  def pick(min_b, :large, 10) do
    Entity2
    |> filter(b >= ^min_b)
    |> take(10)
  end

  def same(min_b, value, value) do
    Entity2
    |> filter(b >= ^min_b)
    |> take(1)
  end

  def same(min_b, _value, _other) do
    Entity2
    |> filter(b >= ^min_b)
    |> take(2)
  end

  def sized(min_b, size) do
    query = filter(Entity2, b >= ^min_b)

    cond do
      size > 10 -> take(query, 10)
      size > 0 -> take(query, ^size)
      true -> query
    end
  end

  def strictly_sized(min_b, size) do
    query = filter(Entity2, b >= ^min_b)

    cond do
      size > 10 -> take(query, 10)
      size > 0 -> take(query, ^size)
    end
  end

  def strict_or_loose(min_b, strict) do
    if strict do
      filter(Entity2, b >= ^min_b)
    else
      filter(Entity2, a: true)
    end
  end

  def windowed(min_b, from, to) when from >= 0 and to > from do
    Entity2
    |> filter(b >= ^min_b)
    |> take(^to)
  end

  def windowed(min_b, _from, _to), do: filter(Entity2, b >= ^min_b)
end
