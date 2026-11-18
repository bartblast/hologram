# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Query.Shape.Module4 do
  # Stages called through the module, trust, and the values a stage records.

  use Hologram.DB

  alias Hologram.Query
  alias Hologram.Test.Fixtures.Entity.Module2
  alias Hologram.Test.Fixtures.Entity.Module26

  def outer_name, do: filter(Module26, any(m <- messages, m.body == name))

  def paged(params) do
    Module2
    |> sort(c: :desc)
    |> paginate(page: ^params.page, size: 10)
  end

  def remote do
    Module2
    |> Query.filter(b in 1..3)
    |> Hologram.Query.take(2)
  end

  def trusted do
    Module2
    |> trust()
    |> filter(b >= -1 and c == "x")
  end
end
