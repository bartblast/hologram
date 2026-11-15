defmodule HologramSyncBenchmark.Entities.Task do
  use Hologram.Entity

  alias HologramSyncBenchmark.Entities.Tenant

  attribute :position, :integer
  attribute :title, :string

  relationship :tenant, Tenant

  # A tenant's members read its tasks and nobody else does: each write reaches only the clients of
  # that tenant's users.
  allow :read, when: any(member <- tenant.members, member.user_id == user_id())
end
