# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.QueryExtractor.Module98 do
  # Functions derived fields hand a query to or get one from.

  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2, as: Entity2

  def apply_all(query, []), do: query

  def apply_all(query, [flag | flags]) do
    query
    |> filter(a == ^flag)
    |> apply_all(flags)
  end

  def drop_ripe(wanted) do
    _ripe = filter(Entity2, a == ^wanted)

    Entity2
  end

  def from_options(opts) do
    opts
    |> Keyword.fetch!(:base)
    |> sort(c)
  end

  def keep(query), do: query

  def label(query), do: "ripe: #{query}"

  def narrow(query, :ripe), do: filter(query, a == true)

  def ripe, do: filter(Entity2, a == true)

  def total(rows) when is_list(rows), do: length(rows)
end
