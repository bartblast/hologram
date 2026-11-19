# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module16 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module1

  relationship :parent, Module1, optional: true

  # A read rule's path may end at a type declaring nothing - the server's verdict answers it - so
  # the type it reaches is in the model a checking client is compiled with only through this
  # relationship.
  allow :read, when: parent.id != nil
end
