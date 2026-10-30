# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module14 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module12
  alias Hologram.Test.Fixtures.Policy.Module2

  attribute :level, :integer, optional: true

  relationship :group, Module2, optional: true
  relationship :owner, Module2, optional: true
  relationship :peer, Module12, optional: true

  allow :delete, via: owner
  allow :read, when: level == 1 or group.public == true
  allow :update, when: level <= peer.level
end
