# credo:disable-for-this-file Credo.Check.Readability.Specs
# An entity a page holds only through a relationship name, with implementations of three protocols.
defmodule Hologram.Test.Fixtures.Compiler.ImplReach.Entity7 do
  use Hologram.Entity

  attribute :label, :string

  allow :read
end

defimpl Hologram.Test.Fixtures.Compiler.ImplReach.Protocol,
  for: Hologram.Test.Fixtures.Compiler.ImplReach.Entity7 do
  alias Hologram.Test.Fixtures.Compiler.ImplReach.Protocol3

  def run(entity), do: Protocol3.export(entity)
end

defimpl Hologram.Test.Fixtures.Compiler.ImplReach.Protocol3,
  for: Hologram.Test.Fixtures.Compiler.ImplReach.Entity7 do
  use Hologram.DB

  alias Hologram.Test.Fixtures.Compiler.ImplReach.Entity8
  alias Hologram.Test.Fixtures.Compiler.ImplReach.Entity9

  def export(_entity), do: filter(Entity8, label == "exported")

  def purge(_entity), do: filter(Entity9, label == "purged")
end

defimpl Hologram.Test.Fixtures.Compiler.ImplReach.Protocol4,
  for: Hologram.Test.Fixtures.Compiler.ImplReach.Entity7 do
  use Hologram.DB

  alias Hologram.Test.Fixtures.Compiler.ImplReach.Entity10

  def run(_entity), do: filter(Entity10, label == "run")
end
