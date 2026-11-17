defmodule HologramSyncBenchmark.Entities.Tenant do
  use Hologram.Entity

  alias HologramSyncBenchmark.Entities.Member

  attribute :name, :string

  relationship :members, [Member], inverse: tenant

  allow :read, when: any(member <- members, member.user_id == user_id())
end
