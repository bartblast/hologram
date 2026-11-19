# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Entity.Module51 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module50

  relationship :parent, Module50, optional: true

  # A read rule may delegate to a type declaring no rule - the server's verdict answers the
  # delegation - so no one may read a row through it, and the type stays out of the client's model.
  allow :read, via: parent
end
