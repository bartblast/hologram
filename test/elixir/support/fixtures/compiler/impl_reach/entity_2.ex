# credo:disable-for-this-file Credo.Check.Readability.Specs
# An entity only server code names, whose implementation queries it in one piece.
defmodule Hologram.Test.Fixtures.Compiler.ImplReach.Entity2 do
  use Hologram.Entity

  attribute :label, :string

  allow :read
end

defimpl Hologram.Test.Fixtures.Compiler.ImplReach.Protocol,
  for: Hologram.Test.Fixtures.Compiler.ImplReach.Entity2 do
  use Hologram.DB

  alias Hologram.Test.Fixtures.Compiler.ImplReach.Entity2

  def run(_entity), do: filter(Entity2, label == "high")
end
