defmodule HologramFeatureTests.Entities.Tool do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.Bench
  alias HologramFeatureTests.Entities.Permit
  alias HologramFeatureTests.Entities.Workshop

  attribute :label, :string

  relationship :bench, Bench, optional: true
  relationship :permits, [Permit], inverse: tool
  relationship :workshop, Workshop, optional: true

  # Each line reads a workshop, a bench or a permit, which only the workshop's owner may read, so
  # anybody else's browser answers it from the server's verdict on the tool: a condition, a
  # delegation, a role held on the bench's workshop and an any over the permits.
  allow :read, when: workshop.open == true
  allow :update, when: workshop.archived == false
  allow :delete, via: {:update, workshop}
  allow :update, only: [:label], to: {:editor, bench.workshop}
  allow :update, only: [:bench], when: any(permit <- permits, permit.approved == true)
end
