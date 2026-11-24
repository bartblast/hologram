# credo:disable-for-this-file Credo.Check.Readability.Specs
# An entity only Entity7's implementation names, whose own implementation names Entity11.
defmodule Hologram.Test.Fixtures.Compiler.ImplReach.Entity8 do
  use Hologram.Entity

  attribute :label, :string

  allow :read
end

defimpl Hologram.Test.Fixtures.Compiler.ImplReach.Protocol,
  for: Hologram.Test.Fixtures.Compiler.ImplReach.Entity8 do
  use Hologram.DB

  alias Hologram.Test.Fixtures.Compiler.ImplReach.Entity11

  def run(_entity), do: filter(Entity11, label == "chained")
end
