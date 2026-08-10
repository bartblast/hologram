# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module2 do
  use Hologram.Entity

  role :admin, scope: :global
  role :member

  allow :read, to: :member
  allow :read_grants, to: :member
end
