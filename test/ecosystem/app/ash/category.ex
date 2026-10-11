# A resource related to itself.
defmodule HologramEcosystemTests.Ash.Category do
  use Ash.Resource,
    domain: HologramEcosystemTests.Ash.Domain,
    data_layer: Ash.DataLayer.Ets

  alias HologramEcosystemTests.Ash.Category

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, public?: true
  end

  relationships do
    belongs_to :parent, Category, attribute_writable?: true, public?: true
  end
end
