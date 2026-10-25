# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module12 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Entity.Module17
  alias Hologram.Test.Fixtures.Policy.Module5

  attribute :level, :integer, optional: true

  relationship :link, Module17, optional: true
  relationship :parent, Module5, optional: true

  allow :archive, when: link.priority == :high
  allow :delete, when: level <= parent.parent.priority
  allow :publish, via: parent.parent
  allow :read, when: parent.parent.public == true
  allow :triage, when: parent.parent.created_at >= ^~U[2026-01-01 00:00:00Z]
  allow :update, to: {:viewer, parent.parent}
end
