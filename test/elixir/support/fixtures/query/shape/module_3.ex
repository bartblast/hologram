# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Query.Shape.Module3 do
  # Queries only known at runtime: one held in a variable, a pinned predicate list and a pinned
  # include spec.

  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2

  def from_variable(query) do
    query
    |> filter(a: true)
    |> take(1)
  end

  def pinned_include(spec), do: include(Module2, ^spec)

  def pinned_predicates(predicates) do
    Module2
    |> filter(^predicates)
    |> take(1)
  end
end
