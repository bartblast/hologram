defmodule HologramFeatureTests.Entities.Pantry do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.Jar

  # Has no protocol implementation, so a page that reaches it only through a row loads none of its
  # code.
  attribute :name, :string

  relationship :jars, [Jar], inverse: pantry, sort: label

  allow :read
end
