# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Query.Shape.Module1 do
  # A pipe of stages on an entity type, written twice.

  use Hologram.DB

  alias Hologram.Test.Fixtures.Entity.Module2

  def read(a) do
    Module2
    |> filter(a == ^a)
    |> sort(b)
    |> take(5)
  end

  def read_again(a) do
    Module2
    |> filter(a == ^a)
    |> sort(b)
    |> take(5)
  end
end
