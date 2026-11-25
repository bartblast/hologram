# credo:disable-for-this-file Credo.Check.Readability.Specs
# The type a page names, which leads to Entity7 and Entity12 by relationship names.
defmodule Hologram.Test.Fixtures.Compiler.ImplReach.Entity6 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Compiler.ImplReach.Entity12
  alias Hologram.Test.Fixtures.Compiler.ImplReach.Entity7

  attribute :label, :string

  relationship :hidden, Entity12, optional: true

  relationship :target, Entity7, optional: true

  allow :read
end
