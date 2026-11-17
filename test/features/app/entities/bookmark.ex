defmodule HologramFeatureTests.Entities.Bookmark do
  use Hologram.Entity

  # Read only by an action, never by a derived field, so no query a page runs reaches its rows -
  # the fill sends them because a page's client code names the type.
  attribute :label, :string

  allow :read
end
