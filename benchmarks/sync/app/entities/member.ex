defmodule HologramSyncBenchmark.Entities.Member do
  use Hologram.Entity

  alias HologramSyncBenchmark.Entities.Tenant
  alias HologramSyncBenchmark.Entities.User

  relationship :tenant, Tenant
  relationship :user, User

  allow :read, when: user_id == user_id()
end
