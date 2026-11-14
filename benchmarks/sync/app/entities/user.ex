defmodule HologramSyncBenchmark.Entities.User do
  use Hologram.Entity, user: true

  attribute :name, :string

  allow :read, when: id == user_id()
end
