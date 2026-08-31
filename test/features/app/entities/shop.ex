defmodule HologramFeatureTests.Entities.Shop do
  use Hologram.Entity

  # Both shapes a time of day comes in: closes_at carries no bounds and may be absent, opens_at
  # carries bounds the browser judges on its own. Both are rendered by the component that lists
  # them, because a time only becomes a struct when a template reads one - which is the client's
  # own boxing, and nothing else here would exercise it.
  attribute :closes_at, :time, optional: true
  attribute :name, :string
  attribute :opens_at, :time, min: ~T[08:00:00], max: ~T[20:00:00], optional: true

  allow :create
  allow :read
end
