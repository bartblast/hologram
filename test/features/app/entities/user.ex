defmodule HologramFeatureTests.Entities.User do
  use Hologram.Entity, user: true

  attribute :email, :string

  allow :read, id: user_id()
end
