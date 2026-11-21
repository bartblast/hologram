# credo:disable-for-this-file Credo.Check.Readability.Specs
defmodule Hologram.Test.Fixtures.Policy.Module49 do
  use Hologram.Entity

  alias Hologram.Test.Fixtures.Policy.Module46
  alias Hologram.Test.Fixtures.Policy.Module47
  alias Hologram.Test.Fixtures.Policy.Module48

  attribute :label, :string, optional: true

  relationship :bench, Module47, optional: true
  relationship :permits, [Module48], inverse: tool
  relationship :workshop, Module46, optional: true

  # Each line reads a workshop, a bench or a permit, rows only their workshop's owner may read, so
  # a reader of the tool may not hold them.
  allow :read, when: workshop.open == true
  allow :update, when: workshop.archived == false
  allow :delete, via: {:update, workshop}
  allow :update, only: [:label], to: {:editor, bench.workshop}
  allow :update, only: [:bench], when: any(permit <- permits, permit.approved == true)
  allow :create, when: workshop.archived == false
  allow :create, as: :draft, when: workshop.archived == false
end
