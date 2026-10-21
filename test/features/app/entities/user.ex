defmodule HologramFeatureTests.Entities.User do
  use Hologram.Entity, user: true

  attribute :email, :string

  allow :read, when: id == user_id()
end
