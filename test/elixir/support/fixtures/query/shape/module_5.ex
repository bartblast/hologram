# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Query.Shape.Module5 do
  # Chains starting at __MODULE__ or a module attribute, pins the stages take, and pinned includes:
  # an include holding a pin is left out of its chain, and a list keeps its known entries.

  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module26

  @entity Module2

  def attribute_head, do: filter(@entity, a: true)

  def module_head, do: take(__MODULE__, 1)

  def pinned_bounds(lo, hi, n) do
    Module2
    |> filter(b in ^lo..^hi)
    |> take(^n)
  end

  def pinned_bounds_stepped(lo, hi) do
    Module2
    |> filter(b in ^lo..^hi//1)
    |> take(3)
  end

  def pinned_include_entry(relationship), do: include(Module26, [topic, ^relationship])

  def pinned_include(a, relationship) do
    Module2
    |> filter(a == ^a)
    |> include([^relationship])
    |> take(5)
  end

  def pinned_pagination(opts) do
    Module2
    |> sort(b)
    |> paginate(^opts)
  end

  def quantified(body), do: filter(Module26, any(m <- messages, m.body == ^body))

  def remote_count, do: Hologram.Query.count(Module2)

  def remote_one, do: Hologram.Query.one(Module2)
end
