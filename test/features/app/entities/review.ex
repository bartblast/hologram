defmodule HologramFeatureTests.Entities.Review do
  use Hologram.Entity

  alias HologramFeatureTests.Entities.Product

  attribute :author_email, :string, format: ~r/@/, optional: true
  attribute :body, :string, max_length: 100, optional: true
  attribute :rating, :integer, in: 1..5

  relationship :product, Product

  allow :read
end
