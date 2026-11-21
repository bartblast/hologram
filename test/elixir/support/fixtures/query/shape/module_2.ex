# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Query.Shape.Module2 do
  # Stages written as nested calls, and the cardinality stages.

  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2

  def counted, do: count(filter(Module2, a: true))

  def first(b), do: one(filter(Module2, b == ^b))
end
