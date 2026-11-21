# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Compiler.ImplReach.Entity3 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Compiler.ImplReach.Entity4

  attribute :label, :string

  relationship :owner, Entity4, optional: true

  allow :read
end
